#!/usr/bin/env python3

import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlparse


SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DESKTOPRENAMER = "https://mqiu.dev/desktoprenamer/appcast"
CURRENT_BUNDLE_ID = "dev.mqiu.DesktopRenamer"
LEGACY_BUNDLE_ID = "com.michaelqiu.DesktopRenamer"
CURRENT_CHANNEL = "dev-mqiu"

ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("desktoprenamer", DESKTOPRENAMER)


def child_text(element, name):
    child = element.find(name)
    return child.text.strip() if child is not None and child.text else ""


def feed_items(root):
    channel = root.find("channel")
    if channel is None:
        raise ValueError("appcast is missing its channel element")
    return channel.findall("item")


def appcast_versions(items):
    current = []
    for item in items:
        target = child_text(item, f"{{{DESKTOPRENAMER}}}targetBundleIdentifier")
        channel = child_text(item, f"{{{SPARKLE}}}channel")
        if target == CURRENT_BUNDLE_ID and channel == CURRENT_CHANNEL:
            build = child_text(item, f"{{{SPARKLE}}}version")
            version = child_text(item, f"{{{SPARKLE}}}shortVersionString")
            enclosure = item.find("enclosure")
            url = enclosure.get("url", "") if enclosure is not None else ""
            if not build.isdecimal() or not url.startswith("https://"):
                raise ValueError("current appcast item has an invalid build number or URL")
            current.append((int(build), version, url))
    if not current:
        raise ValueError("appcast has no current-bundle dev-mqiu release")
    return current


def write_outputs(values, output_path):
    lines = [f"{key}={value}" for key, value in values.items()]
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as file:
            file.write("\n".join(lines) + "\n")
    elif output_path:
        Path(output_path).write_text("\n".join(lines) + "\n", encoding="utf-8")
    else:
        print("\n".join(lines))


def command_latest(args):
    root = ET.parse(args.appcast).getroot()
    latest = max(appcast_versions(feed_items(root)), key=lambda release: release[0])
    values = {
        "previous_build": latest[0],
        "previous_version": latest[1],
        "previous_dmg_url": latest[2],
    }
    write_outputs(values, args.output)
    print(f"{latest[0]}\t{latest[1]}\t{latest[2]}")


def command_normalize(args):
    feed_path = Path(args.appcast)
    contents = feed_path.read_text(encoding="utf-8")
    root = ET.fromstring(contents)
    items = feed_items(root)
    matches = [
        item
        for item in items
        if child_text(item, f"{{{SPARKLE}}}version") == args.build_number
    ]
    if len(matches) != 1:
        raise ValueError(f"expected one appcast item for build {args.build_number}, found {len(matches)}")

    item = matches[0]
    if child_text(item, f"{{{SPARKLE}}}shortVersionString") != args.version:
        raise ValueError("generated appcast marketing version does not match the requested version")
    if child_text(item, f"{{{SPARKLE}}}channel") != CURRENT_CHANNEL:
        raise ValueError("generated appcast item is not on the dev-mqiu channel")

    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("generated appcast item is missing its DMG enclosure")
    dmg_url = enclosure.get("url", "")
    if not dmg_url.startswith(args.download_url_prefix):
        raise ValueError("generated DMG URL does not use the expected release URL")
    if enclosure.get(f"{{{SPARKLE}}}edSignature") != args.dmg_signature:
        raise ValueError("generate_appcast DMG signature differs from sign_update")
    if enclosure.get("length") != str(Path(args.dmg_path).stat().st_size):
        raise ValueError("generated DMG length does not match the file")

    generated_deltas = item.findall(f"{{{SPARKLE}}}deltas/enclosure")
    if len(generated_deltas) != 1:
        raise ValueError(f"expected one delta from the latest release, found {len(generated_deltas)}")
    generated_delta = generated_deltas[0]
    generated_delta_url = generated_delta.get("url", "")
    delta_name = Path(urlparse(generated_delta_url).path).name
    delta_url = args.delta_url_prefix + delta_name
    delta_signature = generated_delta.get(f"{{{SPARKLE}}}edSignature", "")
    delta_from = generated_delta.get(f"{{{SPARKLE}}}deltaFrom", "")
    delta_path = Path(args.delta_directory) / delta_name
    if not generated_delta_url.startswith(args.download_url_prefix):
        raise ValueError("generated delta did not use the expected temporary release URL")
    if delta_from != args.previous_build_number:
        raise ValueError("generated delta does not target the latest current-bundle release")
    if not re.fullmatch(r"[A-Za-z0-9._-]+\.delta", delta_name):
        raise ValueError("generated delta filename contains unsupported characters")
    if not delta_signature or not delta_path.is_file():
        raise ValueError("generated delta is missing its signature or file")
    if generated_delta.get("length") != str(delta_path.stat().st_size):
        raise ValueError("generated delta length does not match the file")

    item_pattern = re.compile(r"(?s)<item(?:\s[^>]*)?>.*?</item>")
    version_pattern = re.compile(
        rf"<sparkle:version>\s*{re.escape(args.build_number)}\s*</sparkle:version>"
    )
    blocks = [match for match in item_pattern.finditer(contents) if version_pattern.search(match.group(0))]
    if len(blocks) != 1:
        raise ValueError("could not locate the new appcast item while preserving its formatting")

    block = blocks[0].group(0)
    generated_delta_attribute = f'url="{generated_delta_url}"'
    if block.count(generated_delta_attribute) != 1:
        raise ValueError("could not locate the generated delta URL while preserving formatting")
    block = block.replace(generated_delta_attribute, f'url="{delta_url}"', 1)

    target_element = (
        "<desktoprenamer:targetBundleIdentifier>"
        f"{CURRENT_BUNDLE_ID}"
        "</desktoprenamer:targetBundleIdentifier>"
    )
    existing_target = re.search(
        r"<desktoprenamer:targetBundleIdentifier>\s*([^<]+)\s*</desktoprenamer:targetBundleIdentifier>",
        block,
    )
    if existing_target:
        if existing_target.group(1).strip() != CURRENT_BUNDLE_ID:
            raise ValueError("generated appcast item has the wrong target bundle identifier")
    else:
        channel_line = re.search(
            r"(?m)^(?P<indent>[ \t]*)<sparkle:channel>\s*dev-mqiu\s*</sparkle:channel>\s*$",
            block,
        )
        if not channel_line:
            raise ValueError("could not locate the generated item channel")
        indent = channel_line.group("indent")
        updated_block = (
            block[: channel_line.end()]
            + "\n"
            + indent
            + target_element
            + block[channel_line.end() :]
        )
        block = updated_block

    contents = contents[: blocks[0].start()] + block + contents[blocks[0].end() :]

    if args.base_appcast:
        base_path = Path(args.base_appcast)
        base_contents = base_path.read_text(encoding="utf-8")
        base_root = ET.fromstring(base_contents)
        base_items = feed_items(base_root)
        if any(child_text(entry, f"{{{SPARKLE}}}version") == args.build_number for entry in base_items):
            raise ValueError("base appcast already contains the new build number")

        base_item = re.search(r"(?m)^(?P<indent>[ \t]*)<item(?:\s[^>]*)?>", base_contents)
        if not base_item:
            raise ValueError("could not locate an item in the base appcast")
        indent = base_item.group("indent")
        contents = (
            base_contents[: base_item.start()]
            + indent
            + block
            + "\n"
            + base_contents[base_item.start() :]
        )

    feed_path.write_text(contents, encoding="utf-8")

    root = ET.parse(feed_path).getroot()
    items = feed_items(root)
    matches = [
        item
        for item in items
        if child_text(item, f"{{{SPARKLE}}}version") == args.build_number
    ]
    if len(matches) != 1:
        raise ValueError("normalized appcast does not contain exactly one new item")
    new_item = matches[0]
    if child_text(new_item, f"{{{DESKTOPRENAMER}}}targetBundleIdentifier") != CURRENT_BUNDLE_ID:
        raise ValueError("new appcast item is missing its current bundle identifier")

    bridge_items = [
        item
        for item in items
        if child_text(item, f"{{{DESKTOPRENAMER}}}targetBundleIdentifier") == LEGACY_BUNDLE_ID
    ]
    if not bridge_items:
        raise ValueError("legacy bundle-ID appcast item was not preserved")

    delta = new_item.find(f"{{{SPARKLE}}}deltas/enclosure")
    if delta is None or delta.get("url") != delta_url:
        raise ValueError("new appcast item is missing the expected delta URL")
    if not delta_url.startswith(args.delta_url_prefix):
        raise ValueError("generated delta URL does not use the expected resource URL")

    write_outputs(
        {
            "delta_name": delta_name,
            "delta_signature": delta_signature,
            "delta_url": delta_url,
            "dmg_url": dmg_url,
        },
        args.output,
    )


def main():
    parser = argparse.ArgumentParser(description="Prepare a current-ID Sparkle release appcast.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    latest = subparsers.add_parser("latest", help="Read the latest current appcast item.")
    latest.add_argument("appcast")
    latest.add_argument("--output")
    latest.set_defaults(run=command_latest)

    normalize = subparsers.add_parser("normalize", help="Validate and add the current bundle target.")
    normalize.add_argument("--appcast", required=True)
    normalize.add_argument("--build-number", required=True)
    normalize.add_argument("--previous-build-number", required=True)
    normalize.add_argument("--version", required=True)
    normalize.add_argument("--download-url-prefix", required=True)
    normalize.add_argument("--delta-url-prefix", required=True)
    normalize.add_argument("--delta-directory", required=True)
    normalize.add_argument("--dmg-signature", required=True)
    normalize.add_argument("--dmg-path", required=True)
    normalize.add_argument("--base-appcast")
    normalize.add_argument("--output")
    normalize.set_defaults(run=command_normalize)

    args = parser.parse_args()
    try:
        args.run(args)
    except (OSError, ET.ParseError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
