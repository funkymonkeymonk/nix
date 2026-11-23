import importlib.util
import sys
import unittest
import urllib.parse

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

    def test_arr_history_accepts_live_lowercase_import_event_names(self):
        client = module.ArrClient(
            "http://radarr.invalid/api/v3",
            "secret",
            request=lambda *_args, **_kwargs: {
                "records": [{"downloadId": "abc", "eventType": "downloadFolderImported"}]
            },
        )
        self.assertEqual(client.import_status("abc"), module.Status.YES)

    def test_arr_history_matches_hash_case_insensitively(self):
        requests = []

        def request(url, **_kwargs):
            requests.append(url)
            return {
                "records": [
                    {"downloadId": "A" * 40, "eventType": "downloadFolderImported"}
                ]
            }

        client = module.ArrClient("http://radarr.invalid/api/v3", "secret", request=request)
        self.assertEqual(client.import_status("a" * 40), module.Status.YES)
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(requests[0]).query)
        self.assertEqual(query["downloadId"], ["A" * 40])

    def test_arr_failed_import_is_distinct_from_no_matching_history(self):
        client = module.ArrClient(
            "http://sonarr.invalid/api/v3",
            "secret",
            request=lambda *_args, **_kwargs: {
                "records": [{"downloadId": "abc", "eventType": "downloadFailedImport"}]
            },
        )
        self.assertEqual(client.import_status("abc"), module.Status.FAILED)

    def test_arr_history_paginates_to_find_failed_import_after_first_page(self):
        pages = []

        def request(url, **_kwargs):
            query = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
            page = int(query["page"][0])
            pages.append(page)
            if page == 1:
                return {
                    "totalRecords": 101,
                    "records": [{"downloadId": "abc", "eventType": "downloadFolderImported"}],
                }
            return {
                "totalRecords": 101,
                "records": [{"downloadId": "abc", "eventType": "downloadFailedImport"}],
            }

        client = module.ArrClient("http://arr.invalid/api/v3", "secret", request=request)
        self.assertEqual(client.import_status("abc"), module.Status.FAILED)
        self.assertEqual(pages, [1, 2])

    def test_collect_statuses_does_not_let_imported_client_hide_unknown_or_failure(self):
        class FakeArrClient:
            def __init__(self, result):
                self.result = result

            def import_status(self, _download_id):
                return self.result

        class FakeJellyfinClient:
            def title_status(self, _title):
                return module.Status.NO

        torrent = [{"id": 19, "download_id": "b" * 40, "title": "Example"}]
        for other_result in (module.Status.UNKNOWN, module.Status.FAILED):
            with self.subTest(other_result=other_result):
                statuses = module.collect_statuses(
                    torrent,
                    arr_clients=[FakeArrClient(module.Status.YES), FakeArrClient(other_result)],
                    jellyfin_client=FakeJellyfinClient(),
                )
                self.assertNotEqual(statuses["19"][0], module.Status.YES)

    def test_collect_statuses_uses_transmission_hash_for_arr_and_keeps_torrent_id_key(self):
        hash_string = "a" * 40

        class FakeArrClient:
            def __init__(self):
                self.download_ids = []

            def import_status(self, download_id):
                self.download_ids.append(download_id)
                return module.Status.YES

        class FakeJellyfinClient:
            def title_status(self, _title):
                return module.Status.NO

        arr = FakeArrClient()
        statuses = module.collect_statuses(
            [{"id": 17, "download_id": hash_string, "title": "Example"}],
            arr_clients=[arr],
            jellyfin_client=FakeJellyfinClient(),
        )

        self.assertEqual(arr.download_ids, [hash_string])
        self.assertEqual(statuses, {"17": (module.Status.YES, module.Status.NO)})

    def test_collect_statuses_marks_missing_transmission_hash_unknown(self):
        class FakeArrClient:
            def import_status(self, _download_id):
                raise AssertionError("must not query Arr without the download hash")

        class FakeJellyfinClient:
            def title_status(self, _title):
                return module.Status.NO

        statuses = module.collect_statuses(
            [{"id": 18, "title": "Example"}],
            arr_clients=[FakeArrClient()],
            jellyfin_client=FakeJellyfinClient(),
        )

        self.assertEqual(statuses, {"18": (module.Status.UNKNOWN, module.Status.NO)})

    def test_jellyfin_requires_one_exact_normalized_title(self):
        def request(url, **_kwargs):
            return {"AccessToken": "token"} if "AuthenticateByName" in url else {
                "Items": [{"Name": "The Matrix"}, {"Name": "Aliens"}]
            }

        client = module.JellyfinClient(
            "http://jellyfin.invalid",
            "user",
            "password",
            request=request,
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

    def test_malformed_api_payloads_are_unknown(self):
        self.assertEqual(
            module.ArrClient("http://arr.invalid", "secret", request=lambda *_args, **_kwargs: []).import_status("abc"),
            module.Status.UNKNOWN,
        )
        self.assertEqual(
            module.JellyfinClient("http://jellyfin.invalid", "user", "password", request=lambda *_args, **_kwargs: {}).title_status("Title"),
            module.Status.UNKNOWN,
        )

    def test_empty_titles_never_match_missing_jellyfin_names(self):
        client = module.JellyfinClient(
            "http://jellyfin.invalid", "user", "password",
            request=lambda url, **_kwargs: {"AccessToken": "token"} if "AuthenticateByName" in url else {"Items": [{}]},
        )
        self.assertEqual(client.title_status(""), module.Status.NO)

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
