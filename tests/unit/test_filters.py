"""Unit tests for filter_plugins/obcell.py.  Run: python3 -m unittest discover -s tests/unit"""
import importlib.util
import pathlib
import unittest

_path = pathlib.Path(__file__).resolve().parents[2] / "filter_plugins" / "obcell.py"
_spec = importlib.util.spec_from_file_location("obcell_filters", _path)
obcell = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(obcell)


class CpuLists(unittest.TestCase):
    def test_range(self):
        self.assertEqual(obcell.obcell_cpu_range([0, 1]), "0-1")
        self.assertEqual(obcell.obcell_cpu_range([3, 0, 2]), "0,2-3")
        self.assertEqual(obcell.obcell_cpu_range([5]), "5")
        self.assertEqual(obcell.obcell_cpu_range([]), "")

    def test_list(self):
        self.assertEqual(obcell.obcell_cpu_list("0-3"), [0, 1, 2, 3])
        self.assertEqual(obcell.obcell_cpu_list("2-3"), [2, 3])
        self.assertEqual(obcell.obcell_cpu_list("0-1,4,6-7\n"), [0, 1, 4, 6, 7])
        self.assertEqual(obcell.obcell_cpu_list(""), [])

    def test_round_trip(self):
        for spec in ["0-3", "0,2-3", "1,3,5", "0-15"]:
            self.assertEqual(obcell.obcell_cpu_range(obcell.obcell_cpu_list(spec)), spec)


class Urls(unittest.TestCase):
    def test_urls(self):
        self.assertEqual(obcell.obcell_urls(["a.local", "10.0.0.2"], 8443),
                         ["https://a.local:8443", "https://10.0.0.2:8443"])
        self.assertEqual(obcell.obcell_urls(["a.local"]), ["https://a.local"])
        self.assertEqual(obcell.obcell_urls(["a.local"], 80, "http"), ["http://a.local:80"])

    def test_ports(self):
        self.assertEqual(obcell.obcell_ports(["a.local", "b"], 5443), ["a.local:5443", "b:5443"])


if __name__ == "__main__":
    unittest.main()
