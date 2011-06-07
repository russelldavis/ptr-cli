#!/bin/bash

cd $(dirname $0)
loginCnt=0

cmdExists() {
  command -v $1 &>/dev/null
}

setCb() {
  cmdExists putclip && putclip -d && return
  cmdExists pbcopy && pbcopy && return
}

getCb() {
  cmdExists getclip && getclip -d && return
  cmdExists pbpaste && pbpaste && return
}

output() {
  echo -e "$1" | setCb
  echo -e "$1"
}

die() {
  echo "$1"
  exit
}

trim() {
  perl -pe 's/^\s+//g; s/\s+$//g'
}

urlEncode() {
  perl -MURI::Escape -MEncode -pe 'chomp; Encode::from_to($_, "cp1252", "utf8"); $_=uri_escape($_);' <<<"$1"
}

escFname() {
  perl -pe 'chomp; s/([^\w\d\-.\$])/sprintf("%%%02X", ord($1))/eg' <<<"$1"
}

makeFname() {
  part1=$(escFname "$1")
  firstChar=$(tr '[:lower:]' '[:upper:]'<<<${part1:0:1})
  [ "$firstChar" == "." ] && firstChar='...'
  echo "data/$firstChar/$part1"@$(escFname "$2")
}

pgWget() {
  wget -U 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.9.1.4) Gecko/20091016 Firefox/3.5.4 (.NET CLR 3.5.30729)' -O - "$@"
}
ptrRemoveBuddy() {
  local urlName="$1"
  ptrBuddyFetch "http://www.pokertableratings.com/buddies.php?action=del_buddy&sid=6&buddy=$urlName&version=5"

  if ! grep -q '<buddies><buddy name=' <<<"$fdata"; then
    echo "PTR error. Unrecognized response:"
    echo "$fdata"
    return
  fi

  echo "$name removed as buddy"
}

ptrAddBuddy() {
  local urlName="$1"
  ptrBuddyFetch "http://www.pokertableratings.com/buddies.php?action=add_buddy&category=TRBuddy&sound=-1&sid=6&buddy=$urlName&version=5"

  if ! grep -q '<buddies><buddy name=' <<<"$fdata"; then
    echo "PTR error. Unrecognized response:"
    echo "$fdata"
    return
  fi

  echo "$name added as buddy"
}

ptrBuddyFetch() {
  url="$1"
  fdata=$(pgWget --load-cookies "data/.cookies" "$url")
  if grep -q '^-1' <<<"$fdata"; then
    echo 'LOGIN REQUIRED'
    ptrLogin
    ptrBuddyFetch "$@"
    return
  fi
}

ptrPremiumFetch() {
  url="$1"
  fname="$2"
  name="$3"

  mkdir -p $(dirname $fname)

  if [ -e "$fname" -a -z "$refresh" ]; then
    fdata=$(<$fname)
  else
    fdata=$(pgWget --load-cookies "data/.cookies" "$url")
    if grep -qi 'You must be logged in' <<<"$fdata"; then
      echo 'LOGIN REQUIRED'
      ptrLogin
      ptrPremiumFetch "$@"
      return
    fi
  fi

  if ! grep -qP '\S' <<<"$fdata"; then
    echo "$name\nNO PREMIUM DATA"
  fi
  
  pf=$(getPremiumSection "Pre-Flop")
  pf3b=$(getPremiumValue "3bet:" <<<"$pf")
  pf4b=$(getPremiumValue "4bet:" <<<"$pf")
  pff3b=$(getPremiumValue "Fold vs. 3Bet:" <<<"$pf")
  pff4b=$(getPremiumValue "Fold vs. 4Bet:" <<<"$pf")
  pfst=$(getPremiumValue "Steals Blinds:" <<<"$pf")
  pffst=$(getPremiumValue "Folded to Steal:" <<<"$pf")
  pffstsb=$(getPremiumValue "Folded SB to Steal:" <<<"$pf")
  pffstbb=$(getPremiumValue "Folded BB to Steal:" <<<"$pf")
}

getPremiumSection() {
  perl -0777 -ne 'm|<h2>'"$1"'</h2>.*?<ul>(.*?)</ul>|s; print $1' <<<"$fdata"
}

getPremiumValue() {
  perl -0777 -ne 'm|'"$1"'</div>.*?>([^<>\s]+)</span>|s; printf("%.0f", $1)'
}

ptrPlayerFetch() {
  url="$1"
  fname="$2"
  name="$3"

  mkdir -p $(dirname $fname)

  if [ -e "$fname" -a -z "$refresh" ]; then
    fdata=$(<$fname)
  else
    fdata=$(pgWget --load-cookies "data/.cookies" "$url")
    if ! grep -qi '>sign out<' <<<"$fdata"; then
      echo 'LOGIN REQUIRED'
      ptrLogin
      ptrPlayerFetch "$@"
      return
    fi
  fi

  if grep -q "We couldn't find a player named" <<<"$fdata"; then
    output "$name\nNO PTR"
    echo "$fdata" > data/errFile.html
    exit
  fi

  #using perl instead of grep because cygwin's grep has problems with this pattern using -qiP (might be the \Q and \E messing it up)
  if perl -ne 'exit 1 if /<title>.*\Q'"$(iconv -f CP1252 -t UTF-8 <<<"$name")"'\E/i' <<<"$fdata"; then
    echo "WARNING: Unexpected response from $url, couldn't find $name in <title>"
    echo "$fdata" > data/.warnFile.html
  fi

  echo "$fdata" > $fname
}

ptrLogin() {
  if ((++loginCnt > 2)); then
    echo "Too many login failures, try again later."
    echo "$fdata" > data/errFile.html
    exit
  fi
  if [ -f data/username.txt ]; then ptrUsername=$(<data/username.txt); else read -rp "Username: " ptrUsername; fi
  if [ -f data/pw.txt ]; then ptrPassword=$(<data/pw.txt); else read -rsp "Password: " ptrPassword; fi

  ptrUsername=$(urlEncode "$ptrUsername")
  ptrPassword=$(urlEncode "$ptrPassword")
  res=$(pgWget --save-cookies "data/.cookies" --post-data "username=$ptrUsername&password=$ptrPassword" 'http://www.pokertableratings.com/login_action.php')

  if ! grep -qP '"success" : true' <<<"$res"; then
    echo 'Error logging into PTR. Response:'
    echo "$res"
    exit
  fi
}

delFiles() {
  shopt -s nullglob
  files=($(makeFname "$1")*)
  shopt -u nullglob

  if [ ${#files[*]} -gt 6 ]; then
    echo 'Something is wrong, too many files would be deleted, pattern "'"$name"'*"'
    exit
  fi
  if [ ${#files[*]} -eq 0 ]; then
    echo 'No files exist'
    exit
  fi

  echo "Deleting:"
  echo "${files[*]}"
  rm -- ${files[*]}
}

doGame() {
  name="$1"
  urlName="$2"
  urlName2="$3"
  game="$4"
  gameTitle=$(perl -pe 's/\$| NLH| SH//g; s/ $/ FR/' <<<"$game")
  gameUrlBase=$(perl -pe 's/([A-Z])LH/$1L/; s/ $/-9/; s/ HU/-2/; s/ SH/-6/; s/\$//g; s|[/ ]|-|g' <<<"$game")
  gameUrl="$gameUrlBase-Hold'em"

  fname=$(makeFname "$name" "analysis-$gameUrl.html")
  url="http://www.pokertableratings.com/stars-player-analysis/$urlName2/$gameUrl"
  ptrPlayerFetch "$url" "$fname" "$name"
  [ -n "$doWeb" ] && cygstart "$url"

  gameBb=$(getBb d_bb100_num)
  gameHands=$(getHands d_handsplayed_num)
  tight=$(getAnalysis tightness_scale)
  aggro=$(getAnalysis aggression_scale)
  sd=$(getAnalysis showdown_scale)

  gameUrl=$(perl -ne 'print lc' <<<"$gameUrl")
  fname=$(makeFname "$name" "grader-$gameUrl.html")
  url="http://www.pokertableratings.com/grader.php?player=$urlName&site=stars&stake=$gameUrl"
  ptrPlayerFetch "$url" "$fname" "$name"
  [ -n "$doWeb" ] && cygstart "$url"

  grades=($(getGrades))

  doPremiumGame "$name" "$urlName" "$urlName2" "$game" "$gameUrlBase"
  output "$name\nTotal: $bb/$hands, $gameTitle: $gameBb/$gameHands\n ~ $tight loose ~ $aggro agg ~ $sd sd ~ ${grades[1]} pfa ~ ${grades[2]} fl ~ ${grades[3]} tu ~ ${grades[4]} riv
 ~ st $pfst ~ 3b $pf3b ~ 4b $pf4b ~ f3b $pff3b ~ f4b $pff4b ~ fs $pffst ~ fsb $pffstsb ~ fbb $pffstbb"

}

doPremiumGame() {
  name="$1"
  urlName="$2"
  urlName2="$3"
  game="$4"
  gameUrlBase="$5"
  IFS=- read stakeLow stakeHigh gameType seats <<<"$gameUrlBase"
  stakes=$(perl -e "print $stakeHigh * 100")

  url="http://www.pokertableratings.com/util/premium_detail.php?site=stars&player=$urlName&filter=cash_low%3D$stakes%26cash_high%3D$stakes%26capnl%3D0%26nl%3D1%26fl%3D0%26pl%3D0%26cappl%3D0%26seats%3D$seats%26gid%3D1%26"

  fname=$(makeFname "$name" "premium-$gameUrlBase.html")
  ptrPremiumFetch "$url" "$fname" "$name"
  [ -n "$doWeb" ] && cygstart "http://www.pokertableratings.com/stars-premium/$urlName2"

}

getGame() {
  grep 'get_hands' <<<"$fdata" | perl -ne '/(?<=>)[^<]+/; print $&'
}

getGames() {
  grep 'get_hands' <<<"$fdata" | perl -ne 'while (m|td width="150".*?>([^<]+).*?>([^<]+).*?>([^<]+).*?>([^<]+)<|g){print ++$i, "\t$1\t$4\t$2\t$3\n"}'
}

getGameByNum() {
  getGames | head -n $1 | tail -1 | cut -f2
}


getAnalysis() {
  grep -P 'id="\Q'$1'\E"' <<<"$fdata" | grep -oP '\d+(?=% of poker players)'
  # old way:
  # grep -P 'id="\Q'$2'\E"' "$1" | perl -pe 's/.*alt=.(\d*).*/$1/'
}

getGrades() {
  grep -C1 'rc_hands_sub_con' <<<"$fdata" | grep optimal | perl -pe 's/% tighter|% less/L/' | perl -pe 's/% looser|% more/H/' | grep -P -o '\d+[LH]'
}

getNamedVal() {
  grep -oP '(?<='$1'">)[-,.\d]+' <<<"$fdata"
}

getBb() {
  getNamedVal "$1" | perl -pe '$_=sprintf("%.0f", $_); s/^-/loser /; s/^(?!l)/winner /'
}

getHands() {
  getNamedVal "$1" | perl -pe 's/,\d{3}$/k/'
}

usage() {
  echo Usage: $(basename $0) "(-c | -n name) [-g game#] [-w] [-r] [-d | -b | -x | -l]"
  echo "-n   specifies the name of the player to be looked up."
  echo "-c   uses the text in the clipboard as the name of the player to be looked up"
  echo "-g   specifies which of the player's game to get stats for (based on the list from -l)"
  echo "-l   shows a list of the games the player has played."
  echo "-w   launches the player's main page, analysis page, and grader page in your web browser."
  echo "-d   deletes the local copy of the player's data."
  echo "-r   refreshes the player's data (equivalent to -d followed by a new request)"
  echo "-b   adds the player to your PTR buddy list."
  echo "-x   removes the player from your PTR buddy list."
}

gameNum=1
while getopts "n:cg:dbxrwl?" flag; do
case $flag in
n) name="$OPTARG";;
c) name=$(getCb | head -n1);;
g) gameNum="$OPTARG";;
d) action="delete";;
b) action="buddy";;
x) action="delbuddy";;
l) action="list";;
w) doWeb="1";;
r) refresh="1";;
\?) usage; exit;;
esac
done

mkdir -p data
touch -a data/.cookies

name=$(trim <<<"$name")
[ -n "$name" ] || die "Name not set (must specify a name with -n, or use -c with a non-empty clipboard)"

if [ "$action" == "delete" ]; then
  delFiles "$name"
  exit
fi

urlName=$(urlEncode "$name")
# some chars (#&+) need to be double escaped on some urls
urlName2=$(perl -pe 's/%(23|26|2B)/%25\1/g' <<<"$urlName")

if [ "$action" == "buddy" ]; then
  ptrAddBuddy "$urlName"
  exit
fi

if [ "$action" == "delbuddy" ]; then
  ptrRemoveBuddy "$urlName"
  exit
fi

fname=$(makeFname "$name" "search.html")
ptrPlayerFetch "http://www.pokertableratings.com/stars-player-search/$urlName2" "$fname" "$name"

if [ "$action" == "list" ]; then
  getGames
  exit
fi

bb=$(getBb ov_bb)
hands=$(getHands ov_hands)
game=$(getGameByNum "$gameNum")

doGame "$name" "$urlName" "$urlName2" "$game"
