#!/usr/bin/env bash
# ESV verse of the day as "text|reference", cached per day; on failure, a fallback verse
# (retry after 10 min). Used by the lock screen, Verse widget and fastfetch.
#   votd.sh            today's verse     votd.sh --random   a fallback-pool verse
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/island"
pool=(
"For I know the plans I have for you, declares the LORD, plans for welfare and not for evil, to give you a future and a hope.|Jeremiah 29:11"
"I can do all things through him who strengthens me.|Philippians 4:13"
"The LORD is my shepherd; I shall not want.|Psalm 23:1"
"Trust in the LORD with all your heart, and do not lean on your own understanding.|Proverbs 3:5"
"Be strong and courageous. Do not be frightened, and do not be dismayed, for the LORD your God is with you wherever you go.|Joshua 1:9"
"Come to me, all who labor and are heavy laden, and I will give you rest.|Matthew 11:28"
"And we know that for those who love God all things work together for good, for those who are called according to his purpose.|Romans 8:28"
"Your word is a lamp to my feet and a light to my path.|Psalm 119:105"
"But they who wait for the LORD shall renew their strength; they shall mount up with wings like eagles.|Isaiah 40:31"
"This is the day that the LORD has made; let us rejoice and be glad in it.|Psalm 118:24"
"Be still, and know that I am God.|Psalm 46:10"
"Casting all your anxieties on him, because he cares for you.|1 Peter 5:7"
"The LORD bless you and keep you; the LORD make his face to shine upon you and be gracious to you.|Numbers 6:24-25"
"Let all that you do be done in love.|1 Corinthians 16:14"
"Fear not, for I am with you; be not dismayed, for I am your God.|Isaiah 41:10"
"In the beginning was the Word, and the Word was with God, and the Word was God.|John 1:1"
)
random() { printf '%s\n' "${pool[RANDOM % ${#pool[@]}]}"; }
[[ $1 == --random ]] && { random; exit; }

today=$(date +%F)
file="$CACHE/votd-$today" fail="$CACHE/votd-fail"
if [[ ! -s $file ]] && [[ -z $(find "$fail" -mmin -10 2>/dev/null) ]]; then
  mkdir -p "$CACHE"
  out=$(curl -fsS -m 2 'https://www.biblegateway.com/votd/get/?format=json&version=ESV' 2>/dev/null |
    python3 -Ic 'import sys,json,html,re
v=json.load(sys.stdin)["votd"]
t=html.unescape(v["content"])
t=re.sub(r"<h[1-6][^>]*>.*?</h[1-6]>\s*"," ",t,flags=re.S)
t=re.sub(r"<[^>]+>"," ",t)
t=re.sub(r"\s+"," ",t)
t=re.sub(r"\s+([,.;:!?])",r"\1",t)
t=t.strip().strip("“”\"")
r=html.unescape(v["display_ref"]).strip()
print(t+"|"+r) if t and r else sys.exit(1)' 2>/dev/null)
  if [[ -n $out ]]; then
    printf '%s\n' "$out" >"$file"; rm -f "$fail"
    find "$CACHE" -maxdepth 1 -name 'votd-20*' ! -name "votd-$today" -delete 2>/dev/null
  else
    : >"$fail"
  fi
fi
if [[ -s $file ]]; then cat "$file"; else random; fi
