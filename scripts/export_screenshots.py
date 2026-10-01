"""Copies named XCTAttachment screenshots out of an exported xcresult into a folder.
Usage: python3 scripts/export_screenshots.py <exported-attachments-dir> <output-dir>"""
import json, os, shutil, sys

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
for test in json.load(open(os.path.join(src, "manifest.json"))):
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", "")
        if not name.endswith(".png"):
            continue
        clean = name.split("_0_")[0] if "_0_" in name else name[:-4]
        shutil.copy(os.path.join(src, attachment["exportedFileName"]), os.path.join(dst, clean + ".png"))
        print(clean)
