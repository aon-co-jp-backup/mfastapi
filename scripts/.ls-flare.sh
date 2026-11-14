cd ~/flare
grep -rn "def percent_decode\|def url_decode\|def urldecode\|def decode_percent\|def percent_" flare | head
grep -n "percent\|url_decode" flare/http/__init__.mojo | head
