const int pingPacketCountMinimum = 1;
const int pingPacketCountMaximum = 10;
const List<int> pingPacketCountChoices = [1, 4, 8, 10];

int validatePingPacketCount(int count) {
  if (count < pingPacketCountMinimum || count > pingPacketCountMaximum) {
    throw RangeError.range(
      count,
      pingPacketCountMinimum,
      pingPacketCountMaximum,
      'count',
      'Ping packet count must be between $pingPacketCountMinimum and $pingPacketCountMaximum.',
    );
  }
  return count;
}
