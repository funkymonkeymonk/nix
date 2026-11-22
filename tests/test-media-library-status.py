import importlib.util
import sys
import unittest

sys.path.insert(0, "modules/nixos/scripts")


spec = importlib.util.spec_from_file_location(
    "media_library_status",
    "modules/nixos/scripts/media-library-status.py",
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

stage_spec = importlib.util.spec_from_file_location(
    "ultra_media_download_stage",
    "modules/nixos/scripts/ultra-media-download-stage.py",
)
stage = importlib.util.module_from_spec(stage_spec)
stage_spec.loader.exec_module(stage)


class MediaLibraryStatusTests(unittest.TestCase):
    def test_normalization_is_case_and_punctuation_insensitive_but_exact(self):
        self.assertEqual(module.normalize_title("The.Matrix (1999)"), "the matrix 1999")
        self.assertNotEqual(module.normalize_title("Alien"), module.normalize_title("Aliens"))

    def test_arr_history_matches_download_id_and_import_event(self):
        client = module.ArrClient(
            "http://radarr.invalid/api/v3",
            "secret",
            request=lambda *_args, **_kwargs: {
                "records": [
                    {"downloadId": "other", "eventType": "DownloadFolderImported"},
                    {"downloadId": "abc", "eventType": "Grabbed"},
                    {"downloadId": "abc", "eventType": "DownloadFolderImported"},
                ]
            },
        )
        self.assertEqual(client.import_status("abc"), module.Status.YES)
        self.assertEqual(client.import_status("missing"), module.Status.NO)

    def test_jellyfin_requires_one_exact_normalized_title(self):
        client = module.JellyfinClient(
            "http://jellyfin.invalid",
            "user",
            "password",
            request=lambda *_args, **_kwargs: {
                "Items": [{"Name": "The Matrix"}, {"Name": "Aliens"}]
            },
        )
        self.assertEqual(client.title_status("The.Matrix"), module.Status.YES)
        self.assertEqual(client.title_status("Alien"), module.Status.NO)

    def test_api_failures_are_unknown(self):
        failing = lambda *_args, **_kwargs: (_ for _ in ()).throw(OSError("unavailable"))
        self.assertEqual(
            module.ArrClient("http://arr.invalid", "secret", request=failing).import_status("abc"),
            module.Status.UNKNOWN,
        )
        self.assertEqual(
            module.JellyfinClient("http://jellyfin.invalid", "user", "password", request=failing).title_status("Title"),
            module.Status.UNKNOWN,
        )

    def test_metrics_add_status_gauges_without_changing_existing_queue_metrics(self):
        content = stage.render_stage_metrics(
            [{"id": 7, "title": "Title", "category": "movies", "total_bytes": 10}],
            status="complete",
            torrents_published=1,
            bytes_transferred=10,
            bytes_reused=0,
            bytes_per_second=1,
            current_torrent_remaining_bytes=0,
            sample_timestamp_seconds=1,
            library_statuses={"7": (module.Status.YES, module.Status.NO)},
        )
        self.assertIn('ultra_media_sync_torrent_imported{category="movies",queue_position="1",title="Title",torrent_id="7"} 1', content)
        self.assertIn('ultra_media_sync_torrent_jellyfin{category="movies",queue_position="1",title="Title",torrent_id="7"} 0', content)
        self.assertIn('ultra_media_sync_torrent_eta_seconds{category="movies",queue_position="1",title="Title",torrent_id="7"} 0', content)


if __name__ == "__main__":
    unittest.main()
