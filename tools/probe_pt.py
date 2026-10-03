"""End-to-end trial of PUGET-TIDES in a scratch folder, normals included."""
import os, shutil, subprocess
src = "tools/pt"; out = "tools/probe_out_pt"; os.makedirs(out, exist_ok=True)
work = "/tmp/pt"; shutil.copytree(src, work, dirs_exist_ok=True)
r = subprocess.run(["bash", "run_job.sh"], cwd=work, capture_output=True, text=True)
open(f"{out}/stdout.txt", "w").write(r.stdout[-20000:] + "\n--- stderr ---\n" + r.stderr[-5000:])
for f in os.listdir(work):
    if f.endswith((".csv", ".txt")) and f not in ("water_level.csv", "pressure.csv"):
        shutil.copy(f"{work}/{f}", out)
print(open(f"{work}/job-log.txt").read() if os.path.exists(f"{work}/job-log.txt") else r.stdout[-3000:])
