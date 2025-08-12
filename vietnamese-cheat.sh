#!/bin/bash

# Vietnamese Typing Cheatsheet for Telex Input Method
# Usage: vietnamese-cheat [section]

show_header() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                Vietnamese Typing Cheatsheet (Telex)          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
}

show_vowels() {
    echo "📝 VOWELS (Nguyên âm):"
    echo "┌─────────────┬─────────────┬─────────────────────────────────┐"
    echo "│ Type        │ Result      │ Example                         │"
    echo "├─────────────┼─────────────┼─────────────────────────────────┤"
    echo "│ aa          │ â           │ caa → câ (that)                 │"
    echo "│ aw          │ ă           │ bawn → băn (worry)              │"
    echo "│ ee          │ ê           │ bee → bê (lamb)                 │"
    echo "│ oo          │ ô           │ coo → cô (aunt)                 │"
    echo "│ ow          │ ơ           │ cow → cơ (body)                 │"
    echo "│ uw          │ ư           │ tuw → tư (think)                │"
    echo "│ dd          │ đ           │ ddaau → đầu (head)              │"
    echo "└─────────────┴─────────────┴─────────────────────────────────┘"
    echo
}

show_tones() {
    echo "🎵 TONE MARKS (Dấu thanh):"
    echo "┌─────────────┬─────────────┬─────────────┬─────────────────────┐"
    echo "│ Add         │ Tone        │ Name        │ Example             │"
    echo "├─────────────┼─────────────┼─────────────┼─────────────────────┤"
    echo "│ + s         │ ́ (acute)    │ sắc         │ as → á              │"
    echo "│ + f         │ ̀ (grave)    │ huyền       │ af → à              │"
    echo "│ + r         │ ̉ (hook)     │ hỏi         │ ar → ả              │"
    echo "│ + x         │ ̃ (tilde)    │ ngã         │ ax → ã              │"
    echo "│ + j         │ ̣ (dot)      │ nặng        │ aj → ạ              │"
    echo "└─────────────┴─────────────┴─────────────┴─────────────────────┘"
    echo
}

show_combinations() {
    echo "🔗 COMBINATIONS (Kết hợp):"
    echo "┌─────────────┬─────────────┬─────────────────────────────────┐"
    echo "│ Type        │ Result      │ Word Example                    │"
    echo "├─────────────┼─────────────┼─────────────────────────────────┤"
    echo "│ aas         │ ấ           │ caas → cấ (level)               │"
    echo "│ oof         │ ồ           │ nooff → nồi (pot)               │"
    echo "│ uwr         │ ở           │ owrr → ờ (hey)                  │"
    echo "│ eex         │ ễ           │ deex → đễ (easy)                │"
    echo "│ awj         │ ặ           │ bawjn → băn (shoot)             │"
    echo "└─────────────┴─────────────┴─────────────────────────────────┘"
    echo
}

show_shortcuts() {
    echo "⌨️  QUICK REFERENCE:"
    echo "vietnamese-cheat vowels    - Show vowel combinations"
    echo "vietnamese-cheat tones     - Show tone marks"
    echo "vietnamese-cheat all       - Show everything"
    echo
}

case "$1" in
    "vowels")
        show_header
        show_vowels
        ;;
    "tones")
        show_header
        show_tones
        ;;
    "combinations"|"combo")
        show_header
        show_combinations
        ;;
    "words"|"common")
        show_header
        show_common_words
        ;;
    "all"|"")
        show_header
        show_vowels
        show_tones
        show_combinations
        show_shortcuts
        ;;
    *)
        show_header
        show_shortcuts
        ;;
esac
