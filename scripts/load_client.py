import sys, time, http.client, threading
from urllib.parse import urlparse
u = urlparse(sys.argv[1]); path = sys.argv[2]; name = sys.argv[3]
N, T = 2000, 16
ok = bad = 0; lock = threading.Lock(); bodies = set()
def work(k):
    global ok, bad
    c = http.client.HTTPConnection(u.hostname, u.port, timeout=30)
    for _ in range(N // T):
        try:
            c.request("GET", path); r = c.getresponse(); b = r.read()
            with lock:
                if r.status == 200: ok += 1; bodies.add(b)
                else: bad += 1
        except Exception:
            with lock: bad += 1
            c = http.client.HTTPConnection(u.hostname, u.port, timeout=30)
t0 = time.time()
ts = [threading.Thread(target=work, args=(i,)) for i in range(T)]
[t.start() for t in ts]; [t.join() for t in ts]
d = time.time() - t0
print("%-28s ok=%d bad=%d distinct_bodies=%d %.0f req/s" % (name, ok, bad, len(bodies), (ok + bad) / d))
