from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ml.tgis.runtime import connect_db, load_runtime, load_yaml


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Queue reinforcement retrain runs from new high-score dataset rows")
    p.add_argument("--config", default="ml/tgis/configs/base.yaml")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--min-new-rows", type=int, default=250)
    p.add_argument("--min-score", type=float, default=0.35)
    p.add_argument("--steps", type=int, default=2000)
    p.add_argument("--learning-rate", type=float, default=0.0005)
    p.add_argument("--max-images", type=int, default=0, help="0 means keep trainer adaptive cap")
    p.add_argument("--source", default="score_reinforcement")
    return p.parse_args()


def _parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    s = str(value).strip()
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


def _to_int(v: Any, default: int = 0) -> int:
    try:
        return int(v)
    except Exception:
        return default


def _to_float(v: Any, default: float = 0.0) -> float:
    try:
        return float(v)
    except Exception:
        return default


def _load_active_clusters_with_last_success(runtime) -> dict[int, datetime]:
    out: dict[int, datetime] = {}
    with connect_db(runtime) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                select c.cluster_id,
                       max(r.ended_at) filter (
                         where r.status = 'success'
                           and r.run_mode <> 'dry_run'
                       ) as last_success_at
                from public.tgis_cluster_registry c
                left join public.tgis_training_runs r
                  on r.cluster_id = c.cluster_id
                where c.is_active = true
                group by c.cluster_id
                order by c.cluster_id
                """
            )
            rows = cur.fetchall()
        conn.commit()
    for cluster_id, last_success_at in rows:
        out[int(cluster_id)] = (
            last_success_at.astimezone(timezone.utc)
            if last_success_at is not None
            else datetime(1970, 1, 1, tzinfo=timezone.utc)
        )
    return out


def _count_new_high_score_rows(
    *,
    metadata_csv: Path,
    active_clusters: dict[int, datetime],
    min_score: float,
) -> dict[int, int]:
    counts: dict[int, int] = {cluster_id: 0 for cluster_id in active_clusters}
    if not metadata_csv.exists():
        return counts

    with metadata_csv.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            cluster_id = _to_int(row.get("cluster_id"), 0)
            if cluster_id not in active_clusters:
                continue
            score = _to_float(row.get("quality_score"), 0.0)
            if score < min_score:
                continue
            ts = (
                _parse_ts(row.get("ts"))
                or _parse_ts(row.get("created_at"))
                or _parse_ts(row.get("updated_at_epic"))
                or _parse_ts(row.get("collected_at"))
            )
            if ts is None:
                continue
            if ts <= active_clusters[cluster_id]:
                continue
            counts[cluster_id] += 1

    return counts


def _has_pending_reinforcement(runtime, cluster_id: int, source: str) -> bool:
    with connect_db(runtime) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                select 1
                from public.tgis_training_runs
                where cluster_id = %s
                  and status in ('queued', 'running')
                  and coalesce(result_json->>'source', '') = %s
                limit 1
                """,
                (cluster_id, source),
            )
            row = cur.fetchone()
        conn.commit()
    return row is not None


def _queue_reinforcement_run(
    *,
    runtime,
    cluster_id: int,
    target_version: str,
    source: str,
    new_rows: int,
    min_score: float,
    steps: int,
    learning_rate: float,
    max_images: int,
) -> None:
    payload = {
        "source": source,
        "new_rows": int(new_rows),
        "min_score": float(min_score),
        "stepsOverride": int(steps),
        "learningRateOverride": float(learning_rate),
    }
    if max_images > 0:
        payload["maxImagesOverride"] = int(max_images)

    with connect_db(runtime) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                insert into public.tgis_training_runs
                (cluster_id, status, run_mode, training_provider, target_version, result_json, created_at, updated_at)
                values (%s, 'queued', 'scheduled', 'fal', %s, %s::jsonb, now(), now())
                """,
                (cluster_id, target_version, json.dumps(payload)),
            )
        conn.commit()


def main() -> None:
    args = parse_args()
    cfg = load_yaml(args.config) or {}
    runtime_cfg = cfg.get("runtime", {}) or {}
    train_cfg = cfg.get("train", {}) or {}
    paths_cfg = cfg.get("paths", {}) or {}
    runtime = load_runtime(args.config)

    min_new_rows = max(1, int(runtime_cfg.get("reinforcement_min_new_rows", args.min_new_rows)))
    min_score = float(runtime_cfg.get("reinforcement_min_score", args.min_score))
    steps = max(10, int(runtime_cfg.get("reinforcement_steps", args.steps)))
    learning_rate = float(runtime_cfg.get("reinforcement_learning_rate", args.learning_rate))
    max_images = int(runtime_cfg.get("reinforcement_max_images", args.max_images))
    source = str(args.source or "score_reinforcement").strip() or "score_reinforcement"

    metadata_csv = Path(paths_cfg.get("training_metadata_csv", "ml/tgis/artifacts/training_metadata.csv"))
    active_clusters = _load_active_clusters_with_last_success(runtime)
    counts = _count_new_high_score_rows(
        metadata_csv=metadata_csv,
        active_clusters=active_clusters,
        min_score=min_score,
    )

    now = datetime.now(timezone.utc)
    queued = 0
    skipped = 0
    for cluster_id in sorted(active_clusters.keys()):
        new_rows = int(counts.get(cluster_id, 0))
        if new_rows < min_new_rows:
            skipped += 1
            continue
        if _has_pending_reinforcement(runtime, cluster_id, source):
            skipped += 1
            continue

        target_version = f"v_reinforce_{now.strftime('%Y%m%d_%H%M')}_c{cluster_id}"
        if args.dry_run:
            print(
                f"[TGIS] dry-run queue cluster={cluster_id} "
                f"new_rows={new_rows} steps={steps} lr={learning_rate} max_images={max_images}"
            )
            queued += 1
            continue

        _queue_reinforcement_run(
            runtime=runtime,
            cluster_id=cluster_id,
            target_version=target_version,
            source=source,
            new_rows=new_rows,
            min_score=min_score,
            steps=steps,
            learning_rate=learning_rate,
            max_images=max_images,
        )
        queued += 1
        print(
            f"[TGIS] queued reinforcement cluster={cluster_id} "
            f"new_rows={new_rows} target={target_version}"
        )

    print(
        f"[TGIS] reinforcement queue done queued={queued} skipped={skipped} "
        f"min_new_rows={min_new_rows} min_score={min_score} "
        f"steps={steps} lr={learning_rate} max_images={max_images} "
        f"trainer={train_cfg.get('fal_trainer_model', 'fal-ai/z-image-turbo-trainer-v2')}"
    )


if __name__ == "__main__":
    main()
