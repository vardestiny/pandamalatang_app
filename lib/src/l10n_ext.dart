import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'models/order.dart';
import 'services/order_poller.dart';

/// Turning server enum names and raw numbers into words, in one place.
///
/// The wire format is English enum names — `PREPARING`, `HOT`, `HALF` — and it
/// stays that way: a German or Chinese word arriving in a JSON field would be
/// untranslatable on a device set to the third language. Every one of them is
/// looked up here instead.
extension OrderText on L {
  /// The status chip on a card. Shouted in the languages that have capitals.
  String statusBadge(String status) => switch (status) {
        'PENDING' => statusBadgePENDING,
        'CONFIRMED' => statusBadgeCONFIRMED,
        'PREPARING' => statusBadgePREPARING,
        'READY' => statusBadgeREADY,
        'COMPLETED' => statusBadgeCOMPLETED,
        // A status this build has never heard of is shown as it arrived rather
        // than hidden: an unlabelled card is still a real order.
        _ => status,
      };

  /// The same statuses, as they read inside a sentence.
  String statusName(String status) => switch (status) {
        'PENDING' => statusNamePENDING,
        'CONFIRMED' => statusNameCONFIRMED,
        'PREPARING' => statusNamePREPARING,
        'READY' => statusNameREADY,
        'COMPLETED' => statusNameCOMPLETED,
        'CANCELLED' => statusNameCANCELLED,
        _ => status,
      };

  /// The step button, named for where the tap leads.
  String stepLabel(String next) => switch (next) {
        'CONFIRMED' => nextCONFIRMED,
        'PREPARING' => nextPREPARING,
        'READY' => nextREADY,
        'COMPLETED' => nextCOMPLETED,
        _ => next,
      };

  String spice(String level) => switch (level) {
        'NONE' => spiceNONE,
        'LIGHT' => spiceLIGHT,
        'MEDIUM' => spiceMEDIUM,
        'HOT' => spiceHOT,
        _ => level,
      };

  String? sugar(String? level) => switch (level) {
        'HALF' => sugarHALF,
        'FULL' => sugarFULL,
        _ => null,
      };

  String? temperature(String? t) => switch (t) {
        'HOT' => tempHOT,
        'ROOM' => tempROOM,
        'ICED' => tempICED,
        _ => null,
      };

  /// How to make a drink, ready to read — temperature first, since that decides
  /// which jug it comes out of. Null when the line is a side dish, or was taken
  /// before the choice existed.
  String? preparation(OrderDrink drink) {
    final parts = [temperature(drink.temperature), sugar(drink.sugarLevel)]
        .whereType<String>()
        .toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Euros, placed the way the reader's language places them: "15,00 €" in
  /// German, "€15.00" in English and Chinese.
  String money(double amount) =>
      NumberFormat.currency(locale: localeName, symbol: '€').format(amount);

  /// A pickup time, always 24-hour. Matches the web console, which is also fixed
  /// at 24-hour: an am/pm slip on a pickup time is an order handed over an hour
  /// late, and the two screens must not read differently.
  String pickupAt(DateTime? time) => time == null
      ? pickupNow
      : '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';

  String date(DateTime when) => DateFormat.yMd(localeName).format(when);

  /// Order number, zero-padded so a column of them lines up.
  String orderNumber(int id) => '#${id.toString().padLeft(4, '0')}';

  /// Connection state, shown permanently rather than only on failure: silence
  /// from a terminal looks identical to a quiet shop, so the screen has to say
  /// which it is.
  String lastSeen(OrderPoller poller) {
    final secs = poller.secondsSinceLastSuccess;
    if (secs == null) return connNever;
    if (secs < 20) return connJustNow;
    if (secs < 120) return connSeconds(secs);
    return connMinutes(secs ~/ 60);
  }
}
