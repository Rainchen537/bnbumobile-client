"""Synthetic regression cases for personal/distribution identity separation."""

import unittest

from check_apple_identity import validate


def fixture(platform="ios", configuration="Release", purpose="local-acceptance"):
    prefix = "developer" if purpose != "distribution" else ""
    base = (prefix + "." if prefix else "") + "me.bnbu.app"
    if platform == "macos":
        base += ".macos"
    if configuration != "Release":
        base += ".debug"
    values = {
        "BNBU_APPLE_IDENTITY_CONFIGURED": "YES",
        "BNBU_APPLE_IDENTITY_PURPOSE": purpose,
        "BNBU_APPLE_DEVELOPER_PREFIX": prefix,
    }
    team = "T" * 10
    if platform == "ios":
        key = "BNBU_IOS_" + ("RELEASE" if configuration == "Release" else "DEVELOPMENT")
        values.update({
            key + "_TEAM": team,
            key + "_BUNDLE_IDENTIFIER": base,
            key + "_WIDGET_BUNDLE_IDENTIFIER": base + ".widgets",
            key + "_WATCH_BUNDLE_IDENTIFIER": base + ".watchkitapp",
            key + "_APP_GROUP_IDENTIFIER": "group." + base,
        })
    else:
        values.update({
            "BNBU_MACOS_TEAM_IDENTIFIER": team,
            "BNBU_MACOS_APP_BUNDLE_IDENTIFIER": base,
            "BNBU_MACOS_WIDGET_BUNDLE_IDENTIFIER": base + ".widgets",
            "BNBU_MACOS_APP_GROUP_IDENTIFIER": team + "." + base,
        })
    return values


class AppleIdentityTests(unittest.TestCase):
    def test_all_platforms_and_lanes(self):
        for platform in ["ios", "macos"]:
            for configuration, purpose in [("Debug", "development"),
                                           ("Profile", "development"),
                                           ("Release", "local-acceptance"),
                                           ("Release", "distribution")]:
                with self.subTest(platform=platform, configuration=configuration, purpose=purpose):
                    validate(fixture(platform, configuration, purpose), platform, configuration)

    def test_personal_release_cannot_distribute(self):
        for platform in ["ios", "macos"]:
            with self.assertRaises(ValueError):
                validate(fixture(platform), platform, "Release", distribution_only=True)

    def test_distribution_can_distribute(self):
        for platform in ["ios", "macos"]:
            validate(fixture(platform, purpose="distribution"), platform, "Release", True)

    def test_personal_cannot_borrow_unprefixed_identity(self):
        values = fixture()
        values["BNBU_IOS_RELEASE_BUNDLE_IDENTIFIER"] = "me.bnbu.app"
        with self.assertRaises(ValueError):
            validate(values, "ios", "Release")

    def test_extension_and_group_must_match(self):
        for key in ["BNBU_IOS_RELEASE_WIDGET_BUNDLE_IDENTIFIER",
                    "BNBU_IOS_RELEASE_WATCH_BUNDLE_IDENTIFIER",
                    "BNBU_IOS_RELEASE_APP_GROUP_IDENTIFIER"]:
            values = fixture()
            values[key] += ".wrong"
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(values, "ios", "Release")

    def test_debug_cannot_use_distribution(self):
        with self.assertRaises(ValueError):
            validate(fixture(purpose="distribution"), "ios", "Debug")

    def test_missing_purpose_and_prefix_fail(self):
        for key in ["BNBU_APPLE_IDENTITY_PURPOSE", "BNBU_APPLE_DEVELOPER_PREFIX",
                    "BNBU_APPLE_IDENTITY_CONFIGURED"]:
            values = fixture()
            del values[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(values, "ios", "Release")

    def test_distribution_cannot_keep_personal_prefix(self):
        values = fixture(purpose="distribution")
        values["BNBU_APPLE_DEVELOPER_PREFIX"] = "developer"
        with self.assertRaises(ValueError):
            validate(values, "ios", "Release")

    def test_macos_group_uses_same_team(self):
        values = fixture("macos")
        values["BNBU_MACOS_APP_GROUP_IDENTIFIER"] = "group.me.bnbu.app.macos"
        with self.assertRaises(ValueError):
            validate(values, "macos", "Release")


if __name__ == "__main__":
    unittest.main()
