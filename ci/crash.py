import json, sys, glob, os, time
files = [f for f in glob.glob(os.path.expanduser("~/Library/Logs/DiagnosticReports/**/*.ips"), recursive=True) if time.time() - os.path.getmtime(f) < 900]
print("CRASH files:", [os.path.basename(f) for f in files])
for f in files:
    if "Afterlight" not in os.path.basename(f):
        continue
    raw = open(f).read().split("\n", 1)[1]
    j = json.loads(raw)
    print("CRASH", os.path.basename(f), j.get("exception"), j.get("termination", {}).get("indicator"))
    asi = j.get("asi")
    if asi: print("CRASH asi", asi)
    imgs = j.get("usedImages", [])
    for t in j.get("threads", []):
        if t.get("triggered"):
            print("CRASH thread", t.get("queue"), t.get("name"))
            for fr in t.get("frames", [])[:30]:
                im = imgs[fr["imageIndex"]].get("name", "?") if "imageIndex" in fr and fr["imageIndex"] < len(imgs) else "?"
                print("CRASH  ", im, fr.get("symbol", "?"), fr.get("sourceFile", ""), fr.get("sourceLine", ""))
