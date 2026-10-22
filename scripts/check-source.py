#!/usr/bin/env python3
"""Linux source checks only. These do not replace an Xcode build or device testing."""
import json
import plistlib
import struct
import xml.etree.ElementTree as ET
from pathlib import Path

from openstep_parser import OpenStepDecoder
from tree_sitter import Language, Parser
import tree_sitter_swift

root = Path(__file__).resolve().parents[1]
parser = Parser(Language(tree_sitter_swift.language()))
errors = []
swift_files = list((root / "MomentCamera").glob("*.swift")) + list((root / "MomentCameraTests").glob("*.swift"))
for path in swift_files:
    tree = parser.parse(path.read_bytes())
    if tree.root_node.has_error:
        errors.append(f"Swift syntax error: {path.relative_to(root)}")

with (root / "MomentCamera/Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryAddUsageDescription", "NSLocationWhenInUseUsageDescription"):
    if not info.get(key):
        errors.append(f"Missing permission description: {key}")

for path in (root / "MomentCamera/Assets.xcassets").rglob("Contents.json"):
    asset = json.loads(path.read_text())
    for image in asset.get("images", []):
        if not (path.parent / image["filename"]).is_file():
            errors.append(f"Missing asset: {image['filename']}")
icon = root / "MomentCamera/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
if icon.exists():
    data = icon.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', data[16:24]) != (1024, 1024) or data[25] not in (0, 2):
        errors.append("App icon must be an opaque 1024x1024 PNG")

with (root / "MomentCamera.xcodeproj/project.pbxproj").open() as stream:
    project = OpenStepDecoder.ParseFromFile(stream)
objects = project["objects"]
for identifier, obj in objects.items():
    for key in ("buildConfigurationList", "fileRef", "containerPortal", "remoteGlobalIDString", "target", "targetProxy", "productReference", "mainGroup", "productRefGroup"):
        if key in obj and obj[key] not in objects:
            errors.append(f"Broken project reference: {identifier}/{key}")
    for key in ("buildConfigurations", "buildPhases", "children", "dependencies", "files", "targets"):
        for reference in obj.get(key, []):
            if reference not in objects:
                errors.append(f"Broken project reference: {identifier}/{key}/{reference}")

for folder in ("MomentCamera", "MomentCameraTests"):
    group = next(obj for obj in objects.values() if obj.get("isa") == "PBXGroup" and obj.get("path") == folder)
    included = {objects[identifier]["path"]: identifier for identifier in group["children"]}
    target = next(obj for obj in objects.values() if obj.get("isa") == "PBXNativeTarget" and obj.get("name") == folder)
    source_phase = next(objects[identifier] for identifier in target["buildPhases"]
                        if objects[identifier]["isa"] == "PBXSourcesBuildPhase")
    compiled = {objects[identifier]["fileRef"] for identifier in source_phase["files"]}
    for path in (root / folder).glob("*.swift"):
        if included.get(path.name) not in compiled:
            errors.append(f"Source absent from target compilation: {folder}/{path.name}")

with (root / "MomentCamera/PrivacyInfo.xcprivacy").open("rb") as stream:
    plistlib.load(stream)

scheme = ET.parse(root / "MomentCamera.xcodeproj/xcshareddata/xcschemes/MomentCamera.xcscheme")
for buildable in scheme.findall(".//BuildableReference"):
    if buildable.attrib["BlueprintIdentifier"] not in objects:
        errors.append("Scheme references a missing target")
if errors:
    raise SystemExit("\n".join(errors))
print(f"PASS: syntax of {len(swift_files)} Swift files, project references, scheme, permissions and app assets")
print("NOT RUN: Swift type checking, iOS build, XCTest, camera or microphone hardware, signing and TestFlight")
