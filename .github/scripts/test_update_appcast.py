import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("update_appcast.py")
CHANGELOG = """# Changelog

## [1.6.0] - 2026-10-19

### Fixed
- Keep <release> & signature bytes
- Another fix

Release notes paragraph.

- Final fix

[1.6.0]: https://example.com/v1.6.0

## [1.5.1] - 2026-10-16
- Older release
"""
EXPECTED_NOTES = """### Fixed
- Keep <release> & signature bytes
- Another fix

Release notes paragraph.

- Final fix
"""
EXPECTED_ITEM = """    <item>
      <title>Version 1.6.0</title>
      <pubDate>Mon, 19 Oct 2026 12:00:00 +0000</pubDate>
      <sparkle:version>42</sparkle:version>
      <sparkle:shortVersionString>1.6.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
<h4>Fixed</h4>
<ul><li>Keep <release> & signature bytes</li><li>Another fix</li></ul>
<p>Release notes paragraph.</p>
<ul><li>Final fix</li></ul>
      ]]></description>
      <enclosure
        url="https://example.com/Gojo-1.6.0.dmg"
        sparkle:edSignature="abc+/DEF=="
        length="17399815"
        type="application/octet-stream" />
    </item>
"""


class UpdateAppcastTests(unittest.TestCase):
    def run_cli(self, root, signature_line):
        (root / "CHANGELOG.md").write_text(CHANGELOG)
        return subprocess.run(
            [
                sys.executable, str(SCRIPT),
                "--version", "1.6.0", "--build", "42",
                "--dmg-url", "https://example.com/Gojo-1.6.0.dmg",
                "--dmg-size", "999",
                "--ed-signature-line", signature_line,
                "--min-system-version", "14.0",
                "--pub-date", "Mon, 19 Oct 2026 12:00:00 +0000",
                "--changelog", str(root / "CHANGELOG.md"),
                "--release-notes-out", str(root / "notes/release.md"),
                "--appcast", str(root / "appcast.xml"),
            ],
            capture_output=True, text=True, check=False,
        )

    def test_literal_cli_output(self):
        for language in ["\n<language>en</language>", ""]:
            for signature in [
                'sparkle:edSignature="abc+/DEF==" length="17399815"',
                'length="17399815" sparkle:edSignature="abc+/DEF=="',
            ]:
                with self.subTest(language=language, signature=signature):
                    with tempfile.TemporaryDirectory() as directory:
                        root = Path(directory)
                        prefix = (
                            '<?xml version="1.0" encoding="utf-8"?>\n'
                            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" '
                            'xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">\n'
                            '<channel>\n<title>Gojo</title>\n<description>Gojo updates</description>'
                            + language
                        )
                        suffix = '\n<item><title>Existing release</title></item>\n</channel>\n</rss>\n'
                        (root / "appcast.xml").write_text(prefix + suffix)
                        result = self.run_cli(root, signature)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(
                            (root / "appcast.xml").read_bytes(),
                            (prefix + "\n" + EXPECTED_ITEM + suffix).encode(),
                        )
                        self.assertEqual(
                            (root / "notes/release.md").read_bytes(), EXPECTED_NOTES.encode()
                        )
                        self.assertEqual(
                            result.stdout,
                            "✓ Inserted appcast item for v1.6.0\n"
                            f"✓ Wrote release notes to {root / 'notes/release.md'}\n",
                        )

    def test_missing_signature_fields_leave_appcast_unchanged(self):
        for signature in ['length="17399815"', 'sparkle:edSignature="abc+/DEF=="']:
            with self.subTest(signature=signature):
                with tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    original = b"<rss><channel><description>Gojo</description></channel></rss>\n"
                    (root / "appcast.xml").write_bytes(original)
                    result = self.run_cli(root, signature)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("Could not parse sign_update output:", result.stderr)
                    self.assertEqual((root / "appcast.xml").read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
