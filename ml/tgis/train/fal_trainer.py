from __future__ import annotations

import csv
import json
import os
import tempfile
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

import requests

from ml.tgis.runtime import load_yaml


DOWNLOAD_TIMEOUT_SEC = 20
DOWNLOAD_WORKERS = 16
MIN_IMAGE_BYTES = 1024


def _ensure_fal_key() -> None:
    if os.getenv("FAL_KEY"):
        return
    fal_api_key = os.getenv("FAL_API_KEY")
    if fal_api_key:
        os.environ["FAL_KEY"] = fal_api_key
        return
    raise RuntimeError("FAL_KEY/FAL_API_KEY is required")


def _load_score_map(training_metadata_csv: Path) -> dict[tuple[str, str], float]:
    if not training_metadata_csv.exists():
        return {}

    score_map: dict[tuple[str, str], float] = {}
    with training_metadata_csv.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            link_code = str(row.get("link_code") or "").strip()
            image_url = str(row.get("image_url") or "").strip()
            if not link_code or not image_url:
                continue
            try:
                score = float(row.get("quality_score") or 0.0)
            except Exception:
                score = 0.0
            score_map[(link_code, image_url)] = score
    return score_map


def _load_metadata(metadata_path: Path, score_map: dict[tuple[str, str], float]) -> list[dict[str, Any]]:
    if not metadata_path.exists():
        raise FileNotFoundError(f"metadata.jsonl not found: {metadata_path}")

    entries: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()

    with metadata_path.open("r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s:
                continue
            row = json.loads(s)
            link_code = str(row.get("link_code") or "").strip()
            image_url = str(row.get("image_url") or "").strip()
            text = str(row.get("text") or "").strip()
            file_name = str(row.get("file_name") or "").strip()
            if not image_url.startswith("http") or not text:
                continue
            key = (link_code, image_url)
            if key in seen:
                continue
            seen.add(key)
            score = score_map.get(key, 0.0)
            entries.append(
                {
                    "link_code": link_code,
                    "image_url": image_url,
                    "text": text,
                    "file_name": file_name,
                    "_score": float(score),
                }
            )

    entries.sort(key=lambda x: float(x.get("_score", 0.0)), reverse=True)
    return entries


def _infer_ext(file_name: str, image_url: str) -> str:
    ext = Path(file_name).suffix.lower().strip()
    if ext in {".jpg", ".jpeg", ".png", ".webp"}:
        return ext
    path_ext = Path(image_url.split("?")[0]).suffix.lower().strip()
    if path_ext in {".jpg", ".jpeg", ".png", ".webp"}:
        return path_ext
    return ".jpg"


def _download_one(entry: dict[str, Any]) -> tuple[str, bytes, str] | None:
    try:
        r = requests.get(str(entry["image_url"]), timeout=DOWNLOAD_TIMEOUT_SEC)
        if r.status_code != 200:
            return None
        content = r.content
        if not content or len(content) < MIN_IMAGE_BYTES:
            return None
        ext = _infer_ext(str(entry.get("file_name") or ""), str(entry["image_url"]))
        caption = str(entry["text"]).strip()
        if not caption:
            return None
        return ext, content, caption
    except Exception:
        return None


def _build_zip(entries: list[dict[str, Any]]) -> tuple[str, int]:
    fd, zip_path = tempfile.mkstemp(prefix="tgis_cluster_", suffix=".zip")
    os.close(fd)
    downloaded = 0

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        with ThreadPoolExecutor(max_workers=DOWNLOAD_WORKERS) as pool:
            futures = [pool.submit(_download_one, e) for e in entries]
            for fut in as_completed(futures):
                row = fut.result()
                if row is None:
                    continue
                ext, img_bytes, caption = row
                downloaded += 1
                stem = f"{downloaded:05d}"
                zf.writestr(f"{stem}{ext}", img_bytes)
                zf.writestr(f"{stem}.txt", caption)

    if downloaded == 0:
        raise RuntimeError("no_images_downloaded_for_training_zip")
    return zip_path, downloaded


def _upload_zip(zip_path: str) -> str:
    _ensure_fal_key()
    import fal_client

    if hasattr(fal_client, "upload_file"):
        return str(fal_client.upload_file(zip_path))
    with open(zip_path, "rb") as f:
        return str(fal_client.upload(f, content_type="application/zip"))


def _submit_training(
    trainer_model: str,
    zip_url: str,
    steps: int,
    learning_rate: float,
    webhook_url: str,
) -> str:
    _ensure_fal_key()
    import fal_client

    result = fal_client.submit(
        trainer_model,
        arguments={
            "image_data_url": zip_url,
            "steps": int(steps),
            "learning_rate": float(learning_rate),
        },
        webhook_url=webhook_url,
    )
    request_id = getattr(result, "request_id", None) or (result.get("request_id") if isinstance(result, dict) else None)
    if not request_id:
        raise RuntimeError("fal_submit_missing_request_id")
    return str(request_id)


def _extract_lora_url(payload: Any) -> str | None:
    if not isinstance(payload, dict):
        return None
    candidates = [
        payload.get("diffusers_lora_file", {}).get("url"),
        payload.get("output", {}).get("diffusers_lora_file", {}).get("url"),
        payload.get("result", {}).get("diffusers_lora_file", {}).get("url"),
    ]
    for c in candidates:
        s = str(c or "").strip()
        if s.startswith("http"):
            return s
    return None


def poll_training_request(*, trainer_model: str, request_id: str) -> dict[str, Any]:
    _ensure_fal_key()
    import fal_client

    try:
        st = fal_client.status(trainer_model, request_id, with_logs=True)
        status_type = type(st).__name__
        payload: dict[str, Any] = {
            "provider_status": "UNKNOWN",
            "raw_status_type": status_type,
            "metrics": {},
            "logs_count": 0,
            "queue_position": None,
            "result": None,
            "output_lora_url": None,
        }

        if status_type == "Queued":
            payload["provider_status"] = "IN_QUEUE"
            payload["queue_position"] = int(getattr(st, "position", 0))
        elif status_type == "InProgress":
            payload["provider_status"] = "IN_PROGRESS"
            logs = list(getattr(st, "logs", []) or [])
            payload["logs_count"] = len(logs)
            payload["metrics"] = {}
        elif status_type == "Completed":
            payload["provider_status"] = "COMPLETED"
            logs = list(getattr(st, "logs", []) or [])
            payload["logs_count"] = len(logs)
            payload["metrics"] = dict(getattr(st, "metrics", {}) or {})
            try:
                result = fal_client.result(trainer_model, request_id)
                payload["result"] = result
                payload["output_lora_url"] = _extract_lora_url(result)
            except Exception as e:
                payload["result_error"] = str(e)
        else:
            payload["provider_status"] = status_type.upper()
        return payload
    except Exception as e:
        msg = str(e)
        if "Unknown status:" in msg:
            raw = msg.split("Unknown status:", 1)[1].strip().upper()
            return {
                "provider_status": raw,
                "raw_status_type": raw,
                "metrics": {},
                "logs_count": 0,
                "queue_position": None,
                "result": None,
                "output_lora_url": None,
                "error": msg,
            }
        raise


def _is_large_payload_error(msg: str) -> bool:
    lowered = msg.lower()
    return (
        "413" in lowered
        or "payload" in lowered
        or "too large" in lowered
        or "timeout" in lowered
        or "body size" in lowered
    )


def submit_cluster_training(
    *,
    config_path: str,
    cluster_id: int,
    steps: int,
    learning_rate: float,
    webhook_url: str,
    max_images_override: int | None = None,
) -> dict[str, Any]:
    cfg = load_yaml(config_path)
    paths_cfg = cfg.get("paths", {}) or {}
    train_cfg = cfg.get("train", {}) or {}

    metadata_path = Path(
        paths_cfg.get("training_dataset_dir", "ml/tgis/artifacts/train_datasets")
    ) / f"cluster_{int(cluster_id):02d}" / "metadata.jsonl"
    training_metadata_csv = Path(
        paths_cfg.get("training_metadata_csv", "ml/tgis/artifacts/training_metadata.csv")
    )

    trainer_model = str(
        os.getenv("TGIS_FAL_TRAINER_MODEL")
        or train_cfg.get("fal_trainer_model")
        or "fal-ai/z-image-turbo-trainer-v2"
    ).strip()
    if not trainer_model:
        raise RuntimeError("missing_fal_trainer_model")

    score_map = _load_score_map(training_metadata_csv)
    entries = _load_metadata(metadata_path, score_map)
    if not entries:
        raise RuntimeError("no_valid_metadata_entries_for_training")

    caps: list[int | None]
    if max_images_override and max_images_override > 0:
        caps = [int(max_images_override)]
    else:
        caps = [None, 4000, 3000, 2500]

    last_error: Exception | None = None
    for cap in caps:
        subset = entries if cap is None else entries[:cap]
        if not subset:
            continue

        zip_path = ""
        try:
            zip_path, downloaded = _build_zip(subset)
            zip_url = _upload_zip(zip_path)
            request_id = _submit_training(
                trainer_model=trainer_model,
                zip_url=zip_url,
                steps=steps,
                learning_rate=learning_rate,
                webhook_url=webhook_url,
            )
            return {
                "training_provider": "fal",
                "trainer_model": trainer_model,
                "fal_request_id": request_id,
                "dataset_zip_url": zip_url,
                "dataset_images_count": downloaded,
                "dataset_cap_used": "all" if cap is None else int(cap),
                "metadata_rows_total": len(entries),
            }
        except Exception as e:
            last_error = e
            msg = str(e)
            if cap != caps[-1] and _is_large_payload_error(msg):
                continue
            raise
        finally:
            if zip_path and Path(zip_path).exists():
                try:
                    Path(zip_path).unlink()
                except Exception:
                    pass

    raise RuntimeError(f"fal_training_submit_failed: {last_error}")
