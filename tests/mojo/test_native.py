import fastapim_native as n


def test_add():
    assert n.add(2, 3) == 5


def test_path_matches():
    assert n.path_matches("/v1/items/{item_id}", "/v1/items/42")
    assert n.path_matches("/", "/")
    assert not n.path_matches("/v1/items/{item_id}", "/v1/items/")
    assert not n.path_matches("/v1/items/{item_id}", "/v1/items/1/2")
    assert not n.path_matches("/a", "/b")
