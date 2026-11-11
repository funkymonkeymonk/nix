import configparser
import contextlib
import http.server
import json
import pathlib
import sys
import tempfile
import threading
import unittest
import urllib.parse


if len(sys.argv) > 1 and pathlib.Path(sys.argv[1]).is_dir():
    SCRIPT_DIR = pathlib.Path(sys.argv.pop(1))
else:
    SCRIPT_DIR = pathlib.Path(__file__).parents[1] / "modules" / "nixos" / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))


class ApiState:
    def __init__(self):
        self.download_clients = []
        self.schemas = []
        self.root_folders = []
        self.remote_path_mappings = []
        self.bazarr_settings = {}
        self.requests = []
        self.next_id = 1


class ApiHandler(http.server.BaseHTTPRequestHandler):
    state = None

    def log_message(self, *_args):
        pass

    def _read_json(self):
        return json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))

    def _write_json(self, value, status=200):
        encoded = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        self.state.requests.append(("GET", self.path, self.headers.get("X-Api-Key")))
        if self.path.endswith("/system/status"):
            self._write_json({"status": "OK"})
        elif self.path.endswith("/downloadclient/schema"):
            self._write_json(self.state.schemas)
        elif self.path.endswith("/downloadclient"):
            self._write_json(self.state.download_clients)
        elif self.path.endswith("/rootfolder"):
            self._write_json(self.state.root_folders)
        elif self.path.endswith("/remotePathMapping"):
            self._write_json(self.state.remote_path_mappings)
        elif self.path == "/bazarr/api/system/settings":
            self._write_json(self.state.bazarr_settings)
        else:
            self._write_json({"error": "not found"}, 404)

    def do_POST(self):
        if self.path == "/bazarr/api/system/settings":
            body_bytes = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            body = {key: values[-1] for key, values in urllib.parse.parse_qs(body_bytes.decode(), keep_blank_values=True).items()}
            self.state.requests.append(("POST", self.path, self.headers.get("X-Api-Key"), body, self.headers.get("Content-Type")))
            for key, value in body.items():
                parts = key.split("-", 2)
                if len(parts) == 3 and parts[0] == "settings":
                    self.state.bazarr_settings.setdefault(parts[1], {})[parts[2]] = value
            self._write_json(self.state.bazarr_settings)
            return
        body = self._read_json()
        self.state.requests.append(("POST", self.path, self.headers.get("X-Api-Key"), body))
        if self.path.endswith("/downloadclient"): 
            body["id"] = self.state.next_id
            self.state.next_id += 1
            self.state.download_clients.append(body)
            self._write_json(body, 201)
        elif self.path.endswith("/rootfolder"):
            body["id"] = self.state.next_id
            self.state.next_id += 1
            self.state.root_folders.append(body)
            self._write_json(body, 201)
        elif self.path.endswith("/remotePathMapping"):
            body["id"] = self.state.next_id
            self.state.next_id += 1
            self.state.remote_path_mappings.append(body)
            self._write_json(body, 201)
        else:
            self._write_json({"error": "not found"}, 404)

    def do_PUT(self):
        body = self._read_json()
        self.state.requests.append(("PUT", self.path, self.headers.get("X-Api-Key"), body))
        item_id = int(self.path.rsplit("/", 1)[1])
        collection = (
            self.state.download_clients
            if "/downloadclient/" in self.path
            else self.state.remote_path_mappings
        )
        for index, item in enumerate(collection):
            if item.get("id") == item_id:
                collection[index] = body
                self._write_json(body)
                return
        self._write_json({"error": "not found"}, 404)


@contextlib.contextmanager
def running_api(state):
    ApiHandler.state = state
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ApiHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown()
        thread.join()
        server.server_close()


def write_secret(directory, name, value):
    path = directory / name
    path.write_text(value)
    return str(path)


class ServarrReconciliationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = pathlib.Path(self.temporary.name)
        self.state = ApiState()
        self.state.schemas = [
            {
                "id": 0,
                "name": "",
                "implementation": "Transmission",
                "enable": True,
                "fields": [
                    {"name": "host", "value": ""},
                    {"name": "port", "value": 9091},
                    {"name": "useSsl", "value": False},
                    {"name": "urlBase", "value": ""},
                    {"name": "username", "value": ""},
                    {"name": "password", "value": ""},
                    {"name": "unmanaged", "value": "schema-default"},
                ],
            }
        ]
        self.config_xml = self.directory / "config.xml"
        self.config_xml.write_text("<Config><ApiKey>arr-api-key</ApiKey></Config>")
        self.transmission = {
            "rpcUrl": {"secret": write_secret(self.directory, "rpc-url", "https://seed.example:443/transmission/rpc")},
            "username": {"secret": write_secret(self.directory, "rpc-user", "rpc-user")},
            "password": {"secret": write_secret(self.directory, "rpc-password", "rpc-secret")},
            "remotePath": {"secret": write_secret(self.directory, "remote-path", "/downloads/complete")},
            "localPath": "/srv/media/.arr-staging",
        }

    def tearDown(self):
        self.temporary.cleanup()

    def test_reconciliation_creates_download_client_root_and_remote_mapping(self):
        from servarr_reconcile import reconcile

        with running_api(self.state) as server:
            reconcile(
                {
                    "baseUrl": f"{server}/api/v3",
                    "configXml": str(self.config_xml),
                    "rootFolders": ["/srv/media/movies"],
                    "transmission": self.transmission,
                }
            )

        self.assertEqual(len(self.state.download_clients), 1)
        client = self.state.download_clients[0]
        self.assertEqual(client["implementation"], "Transmission")
        self.assertEqual(client["name"], "Transmission")
        fields = {field["name"]: field["value"] for field in client["fields"]}
        self.assertEqual(fields["host"], "seed.example")
        self.assertEqual(fields["port"], 443)
        self.assertTrue(fields["useSsl"])
        self.assertEqual(fields["urlBase"], "/transmission")
        self.assertEqual(fields["username"], "rpc-user")
        self.assertEqual(fields["password"], "rpc-secret")
        self.assertEqual(fields["unmanaged"], "schema-default")
        self.assertEqual(self.state.root_folders[0]["path"], "/srv/media/movies")
        self.assertEqual(self.state.remote_path_mappings[0]["host"], "seed.example")
        self.assertEqual(self.state.remote_path_mappings[0]["remotePath"], "/downloads/complete")
        self.assertEqual(self.state.remote_path_mappings[0]["localPath"], "/srv/media/.arr-staging")
        self.assertTrue(all(request[2] == "arr-api-key" for request in self.state.requests))

    def test_reconciliation_is_idempotent_and_never_deletes(self):
        from servarr_reconcile import reconcile

        with running_api(self.state) as server:
            config = {
                "baseUrl": f"{server}/api/v3",
                "configXml": str(self.config_xml),
                "rootFolders": ["/srv/media/movies"],
                "transmission": self.transmission,
            }
            reconcile(config)
            request_count = len(self.state.requests)
            reconcile(config)

        self.assertEqual(len(self.state.download_clients), 1)
        self.assertEqual(len(self.state.root_folders), 1)
        self.assertEqual(len(self.state.remote_path_mappings), 1)
        self.assertFalse(any(request[0] == "DELETE" for request in self.state.requests))
        self.assertGreater(len(self.state.requests), request_count)

    def test_existing_client_update_preserves_unmanaged_fields(self):
        from servarr_reconcile import reconcile

        self.state.download_clients = [
            {
                "id": 42,
                "name": "Transmission",
                "implementation": "Transmission",
                "enable": True,
                "fields": [
                    {"name": "host", "value": "old.example"},
                    {"name": "port", "value": 9091},
                    {"name": "useSsl", "value": False},
                    {"name": "urlBase", "value": ""},
                    {"name": "username", "value": ""},
                    {"name": "password", "value": "old-secret"},
                    {"name": "unmanaged", "value": "keep-me"},
                ],
            }
        ]
        with running_api(self.state) as server:
            reconcile(
                {
                    "baseUrl": f"{server}/api/v3",
                    "configXml": str(self.config_xml),
                    "rootFolders": [],
                    "transmission": self.transmission,
                }
            )

        client = self.state.download_clients[0]
        fields = {field["name"]: field["value"] for field in client["fields"]}
        self.assertEqual(client["id"], 42)
        self.assertEqual(fields["host"], "seed.example")
        self.assertEqual(fields["password"], "rpc-secret")
        self.assertEqual(fields["unmanaged"], "keep-me")
        self.assertTrue(any(request[0] == "PUT" for request in self.state.requests))

    def test_ambiguous_existing_client_fails_without_mutation(self):
        from servarr_reconcile import reconcile

        duplicate = {
            "id": 1,
            "name": "Transmission",
            "implementation": "Transmission",
            "enable": True,
            "fields": [],
        }
        self.state.download_clients = [dict(duplicate), {**duplicate, "id": 2}]
        before = json.loads(json.dumps(self.state.download_clients))

        with running_api(self.state) as server:
            with self.assertRaisesRegex(RuntimeError, "ambiguous"):
                reconcile(
                    {
                        "baseUrl": f"{server}/api/v3",
                        "configXml": str(self.config_xml),
                        "rootFolders": [],
                        "transmission": self.transmission,
                    }
                )

        self.assertEqual(self.state.download_clients, before)
        self.assertFalse(any(request[0] in {"POST", "PUT", "DELETE"} for request in self.state.requests))


class BazarrReconciliationTests(unittest.TestCase):
    def test_bazarr_connections_update_without_replacing_other_settings(self):
        from bazarr_reconcile import reconcile

        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            bazarr_key = write_secret(directory, "bazarr-key", "bazarr-key-value")
            sonarr_key = write_secret(directory, "sonarr-key", "sonarr-key-value")
            radarr_key = write_secret(directory, "radarr-key", "radarr-key-value")
            state = ApiState()
            state.bazarr_settings = {
                "general": {"base_url": "/bazarr", "use_sonarr": False, "use_radarr": False},
                "sonarr": {"ip": "seedbox.local", "port": 8989, "base_url": "/", "ssl": False, "apikey": "old-sonarr-key", "only_monitored": True, "series_sync": 17, "episodes_sync": 23},
                "radarr": {"ip": "seedbox.local", "port": 7878, "base_url": "/", "ssl": False, "apikey": "old-radarr-key", "only_monitored": True, "movies_sync": 19},
                "unmanaged-setting": "preserve",
            }

            with running_api(state) as server:
                config = {
                    "bazarrBaseUrl": f"{server}/bazarr",
                    "bazarrApiKeyFile": bazarr_key,
                    "useSonarr": False,
                    "useRadarr": False,
                    "sonarr": {"baseUrl": "http://127.0.0.1:8989/sonarr", "apiKeyFile": sonarr_key},
                    "radarr": {"baseUrl": "http://127.0.0.1:7878/radarr", "apiKeyFile": radarr_key},
                }
                reconcile(config)
                writes_after_first_sync = sum(request[0] == "POST" for request in state.requests)
                reconcile(config)

        self.assertEqual(sum(request[0] == "POST" for request in state.requests), writes_after_first_sync)

        self.assertEqual(state.bazarr_settings["unmanaged-setting"], "preserve")
        self.assertFalse(state.bazarr_settings["general"]["use_sonarr"])
        self.assertFalse(state.bazarr_settings["general"]["use_radarr"])
        self.assertEqual(state.bazarr_settings["general"]["base_url"], "")
        self.assertEqual(state.bazarr_settings["sonarr"]["apikey"], "sonarr-key-value")
        self.assertEqual(state.bazarr_settings["radarr"]["apikey"], "radarr-key-value")
        self.assertEqual(state.bazarr_settings["sonarr"]["ip"], "127.0.0.1")
        self.assertEqual(state.bazarr_settings["radarr"]["ip"], "127.0.0.1")
        self.assertEqual(state.bazarr_settings["sonarr"]["base_url"], "/sonarr")
        self.assertEqual(state.bazarr_settings["radarr"]["base_url"], "/radarr")
        self.assertTrue(state.bazarr_settings["sonarr"]["only_monitored"])
        self.assertEqual(state.bazarr_settings["sonarr"]["series_sync"], 17)
        self.assertEqual(state.bazarr_settings["sonarr"]["episodes_sync"], 23)
        self.assertTrue(state.bazarr_settings["radarr"]["only_monitored"])
        self.assertEqual(state.bazarr_settings["radarr"]["movies_sync"], 19)
        form_posts = [request for request in state.requests if request[0] == "POST"]
        self.assertEqual(len(form_posts), 1)
        self.assertTrue(all(request[2] == "bazarr-key-value" for request in form_posts))
        self.assertTrue(all(request[4] == "application/x-www-form-urlencoded" for request in form_posts))


class MylarConfigTests(unittest.TestCase):
    def test_runtime_ini_expands_secrets_and_preserves_typed_settings(self):
        from mylar3_config import render_ini, write_config

        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            secret_path = directory / "api-key"
            secret_path.write_text("mylar-secret")
            settings = {
                "General": {"DESTINATION_DIR": "/srv/media/comics", "CREATE_FOLDERS": True},
                "API": {"API_KEY": {"secret": str(secret_path)}},
            }
            rendered = render_ini(settings, "[Unmanaged]\nKeep = this\n")
            settings_file = directory / "settings.json"
            config_file = directory / "config.ini"
            settings_file.write_text(json.dumps(settings))
            write_config(str(settings_file), str(config_file))
            parser = configparser.ConfigParser()
            parser.read_string(rendered)
            persisted = configparser.ConfigParser()
            self.assertEqual(persisted.read(config_file), [str(config_file)])
            self.assertEqual(config_file.stat().st_mode & 0o777, 0o600)

        self.assertEqual(parser.get("General", "destination_dir"), "/srv/media/comics")
        self.assertTrue(parser.getboolean("General", "create_folders"))
        self.assertEqual(parser.get("API", "api_key"), "mylar-secret")
        self.assertEqual(parser.get("Unmanaged", "keep"), "this")


class RuntimeApiKeyTests(unittest.TestCase):
    def test_api_key_extractor_reads_xml_and_yaml_without_printing_key(self):
        from extract_media_api_key import extract_key, write_key

        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            xml_config = directory / "config.xml"
            yaml_config = directory / "config.yaml"
            output = directory / "run" / "api-key"
            xml_config.write_text("<Config><ApiKey>xml-key</ApiKey></Config>")
            yaml_config.write_text("auth:\n  apikey: yaml-key\n")
            self.assertEqual(extract_key("xml", xml_config), "xml-key")
            self.assertEqual(extract_key("yaml", yaml_config), "yaml-key")
            write_key(output, "yaml-key")
            self.assertEqual(output.read_text().strip(), "yaml-key")
            self.assertEqual(output.stat().st_mode & 0o777, 0o640)

    def test_remote_transmission_rpc_requires_tls(self):
        from servarr_reconcile import transmission_fields
        from media_api_reconcile import ReconciliationError

        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            config = {
                "rpcUrl": {"secret": write_secret(directory, "url", "http://seed.example:9091/transmission/rpc")},
                "username": {"secret": write_secret(directory, "user", "rpc-user")},
                "password": {"secret": write_secret(directory, "password", "rpc-secret")},
                "remotePath": {"secret": write_secret(directory, "remote", "/downloads")},
                "localPath": "/srv/media/.arr-staging",
            }
            with self.assertRaisesRegex(ReconciliationError, "HTTPS"):
                transmission_fields(config)


if __name__ == "__main__":
    unittest.main()
