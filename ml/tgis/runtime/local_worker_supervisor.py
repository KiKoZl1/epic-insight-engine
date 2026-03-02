from __future__ import annotations

import argparse
import subprocess
import sys
import time
from datetime import datetime, timezone


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Run local TGIS worker loop (heartbeat + queue + cost sync)")
    p.add_argument("--config", default="ml/tgis/configs/base.yaml")
    p.add_argument("--max-training-runs", type=int, default=1)
    p.add_argument("--poll-seconds", type=int, default=20)
    p.add_argument("--skip-cost-sync", action="store_true")
    p.add_argument("--once", action="store_true")
    return p.parse_args()


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _run_worker_tick(*, config: str, max_training_runs: int, skip_cost_sync: bool) -> int:
    cmd = [
        sys.executable,
        "-m",
        "ml.tgis.runtime.worker_tick",
        "--config",
        config,
        "--max-training-runs",
        str(max(1, int(max_training_runs))),
    ]
    if skip_cost_sync:
        cmd.append("--skip-cost-sync")
    proc = subprocess.run(cmd, check=False)
    return int(proc.returncode)


def main() -> None:
    args = parse_args()
    poll_seconds = max(5, int(args.poll_seconds))

    while True:
        tick_started = time.time()
        print(f"[TGIS] local worker tick start ts={_utc_now()}")
        try:
            rc = _run_worker_tick(
                config=args.config,
                max_training_runs=args.max_training_runs,
                skip_cost_sync=bool(args.skip_cost_sync),
            )
            if rc == 0:
                print(f"[TGIS] local worker tick ok ts={_utc_now()}")
            else:
                print(f"[TGIS] local worker tick failed rc={rc} ts={_utc_now()}")
        except Exception as e:
            print(f"[TGIS] local worker supervisor exception={e} ts={_utc_now()}")

        if args.once:
            break

        elapsed = int(time.time() - tick_started)
        sleep_for = max(1, poll_seconds - elapsed)
        time.sleep(sleep_for)


if __name__ == "__main__":
    main()
