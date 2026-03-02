from __future__ import annotations

import argparse
import ast
import csv
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

from ml.tgis.runtime import connect_db, load_runtime, load_yaml


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Sync top reference images by cluster/tag for TGIS i2i")
    p.add_argument("--config", default="ml/tgis/configs/base.yaml")
    p.add_argument("--top-n", type=int, default=3)
    p.add_argument("--min-score", type=float, default=0.0)
    return p.parse_args()


def _to_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return default


def _to_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return default


def _parse_tags(value: str) -> list[str]:
    s = (value or "").strip()
    if not s:
        return []
    if s.startswith("[") and s.endswith("]"):
        try:
            parsed = ast.literal_eval(s)
            if isinstance(parsed, list):
                return [str(x).strip().lower() for x in parsed if str(x).strip()]
        except Exception:
            return []
    return [x.strip().lower() for x in s.split(",") if x.strip()]


def _normalize_tag(value: str) -> str:
    return " ".join((value or "").strip().lower().split())


def main() -> None:
    args = parse_args()
    cfg = load_yaml(args.config)
    runtime = load_runtime(args.config)

    training_metadata_csv = Path(
        cfg.get("paths", {}).get("training_metadata_csv", "ml/tgis/artifacts/training_metadata.csv")
    )
    if not training_metadata_csv.exists():
        payload = {
            "ok": False,
            "reason": "training_metadata_csv_not_found",
            "path": str(training_metadata_csv),
        }
        print(json.dumps(payload, ensure_ascii=False))
        return

    top_n = max(1, int(args.top_n))
    min_score = float(args.min_score)

    per_cluster_tag: dict[tuple[int, str], list[dict[str, Any]]] = defaultdict(list)
    per_cluster_best: dict[int, dict[str, Any]] = {}

    with training_metadata_csv.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            cluster_id = _to_int(row.get("cluster_id"))
            if cluster_id <= 0:
                continue
            image_url = str(row.get("image_url") or "").strip()
            link_code = str(row.get("link_code") or "").strip()
            if not image_url.startswith("http") or not link_code:
                continue
            quality_score = _to_float(row.get("quality_score"), 0.0)
            if quality_score < min_score:
                continue

            tags: set[str] = set()
            tags.update(_parse_tags(str(row.get("tags") or "")))
            for extra_key in ("tag_group", "map_type", "cluster"):
                extra = _normalize_tag(str(row.get(extra_key) or ""))
                if extra:
                    tags.add(extra)

            if not tags:
                tags.add("default")

            item = {
                "cluster_id": cluster_id,
                "link_code": link_code,
                "image_url": image_url,
                "quality_score": quality_score,
            }

            prev_best = per_cluster_best.get(cluster_id)
            if prev_best is None or item["quality_score"] > prev_best["quality_score"]:
                # Keep one default reference candidate per cluster.
                # Pick the first semantic tag (if any) to store in cluster registry.
                first_tag = sorted(tags)[0]
                per_cluster_best[cluster_id] = {**item, "reference_tag": first_tag}

            for tag in tags:
                per_cluster_tag[(cluster_id, tag)].append(item)

    reference_rows: list[tuple[int, str, int, str, str, float]] = []
    for (cluster_id, tag), items in per_cluster_tag.items():
        # top quality desc, deduplicate image/link.
        seen: set[tuple[str, str]] = set()
        rank = 0
        for item in sorted(items, key=lambda x: float(x["quality_score"]), reverse=True):
            key = (str(item["link_code"]), str(item["image_url"]))
            if key in seen:
                continue
            seen.add(key)
            rank += 1
            reference_rows.append(
                (
                    cluster_id,
                    tag,
                    rank,
                    str(item["link_code"]),
                    str(item["image_url"]),
                    float(item["quality_score"]),
                )
            )
            if rank >= top_n:
                break

    with connect_db(runtime) as conn:
        with conn.cursor() as cur:
            cur.execute("delete from public.tgis_reference_images")
            if reference_rows:
                cur.executemany(
                    """
                    insert into public.tgis_reference_images
                    (cluster_id, tag_group, rank, link_code, image_url, quality_score, updated_at)
                    values (%s, %s, %s, %s, %s, %s, now())
                    on conflict (cluster_id, tag_group, rank)
                    do update set
                      link_code = excluded.link_code,
                      image_url = excluded.image_url,
                      quality_score = excluded.quality_score,
                      updated_at = now()
                    """,
                    reference_rows,
                )

            for cluster_id, best in per_cluster_best.items():
                cur.execute(
                    """
                    update public.tgis_cluster_registry
                    set reference_image_url = %s,
                        reference_tag = %s,
                        reference_updated_at = now(),
                        updated_at = now()
                    where cluster_id = %s
                    """,
                    (
                        str(best["image_url"]),
                        str(best["reference_tag"]),
                        int(cluster_id),
                    ),
                )
        conn.commit()

    payload = {
        "ok": True,
        "training_rows": len(per_cluster_tag),
        "reference_rows": len(reference_rows),
        "clusters_with_default_reference": len(per_cluster_best),
        "top_n": top_n,
        "min_score": min_score,
    }
    print(json.dumps(payload, ensure_ascii=False))


if __name__ == "__main__":
    main()

