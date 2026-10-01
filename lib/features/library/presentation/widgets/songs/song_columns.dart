/// From this list width a desktop songs list shows two columns.
const double songTwoColumnWidth = 1100;

/// How many columns the songs list shows. Two only on desktop, on a list
/// at least [songTwoColumnWidth] wide, and not while searching (a search
/// hit can add a lyric snippet, which makes rows different heights).
int songColumnsFor(
  double width, {
  required bool desktop,
  required bool searching,
}) {
  if (!desktop || searching || !width.isFinite) return 1;
  return width >= songTwoColumnWidth ? 2 : 1;
}
