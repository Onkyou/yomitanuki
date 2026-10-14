/// Characters a dictionary surface never crosses (WP3 D3.5): whitespace,
/// Japanese punctuation and brackets, ASCII `!?,.`. Shared by the lookup
/// that stops at them and the line glosser that does not look them up.
const Set<int> lookupBreaks = {
  0x20, 0x09, 0x0A, 0x0D, 0x3000, // spaces, tab, newline, ideographic space
  0x3001, 0x3002, 0xFF01, 0xFF1F, // 、 。 ！ ？
  0x300C, 0x300D, 0x300E, 0x300F, // 「 」 『 』
  0x2026, 0x2025, 0x30FB, // … ‥ ・
  0xFF08, 0xFF09, 0xFF5E, // （ ） ～
  0x21, 0x3F, 0x2C, 0x2E, // ! ? , .
};
