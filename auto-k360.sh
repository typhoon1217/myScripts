#!/bin/sh
URL="https://us06web.zoom.us/postattendee?mn=HmaSkyfsBaZJnbX7MEZVZQ1FbO99ecEhuHWo.SRJ0jdSxS7IEWhzF"
PNG_FILE="$HOME/Pictures/hrd.png"
open_resource() {
  resource="$1"

  case "$(uname -s)" in
  Darwin*)
    open "$resource"
    ;;
  Linux*)
    if command -v xdg-open >/dev/null; then
      xdg-open "$resource"
    elif command -v gio >/dev/null; then
      gio open "$resource"
    else
      echo "오류: Linux용 열기 명령을 찾을 수 없습니다."
      exit 1
    fi
    ;;
  CYGWIN* | MINGW* | MSYS*)
    start "" "$resource"
    ;;
  *)
    echo "지원되지 않는 운영 체제입니다"
    exit 1
    ;;
  esac
}

if [ "$1" = "url" ]; then
  echo "Opening URL: $URL"
  echo "URL 열기: $URL"
  open_resource "$URL"
elif [ "$1" = "img" ] || [ "$1" = "png" ]; then
  if [ -f "$PNG_FILE" ]; then
    echo "Opening PNG: $PNG_FILE"
    echo "PNG 파일 열기: $PNG_FILE"
    open_resource "$PNG_FILE"
  else
    echo "Error: PNG file does not exist: $PNG_FILE"
    echo "오류: PNG 파일이 존재하지 않습니다: $PNG_FILE"
    exit 1
  fi
else
  echo "URL과 PNG 파일 모두 열기"
  echo "URL 열기: $URL"
  open_resource "$URL"
  if [ -f "$PNG_FILE" ]; then
    echo "PNG 파일 열기: $PNG_FILE"
    open_resource "$PNG_FILE"
  else
    echo "오류: PNG 파일이 존재하지 않습니다: $PNG_FILE"
  fi
fi
echo "작업이 완료되었습니다."
exit 0
