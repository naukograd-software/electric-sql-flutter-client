// Core types ported from TS to Dart

typedef JsonMap = Map<String, dynamic>;

// In TS Value is recursive. In Dart we represent values as dynamic
// but keep helper type aliases for readability.
typedef SqlValue = dynamic; // String | num | bool | BigInt-like | null | List | Map

typedef Row = Map<String, SqlValue>;

// Offset: '-1' | `${number}_${number}` | `${bigint}_${number}`
typedef Offset = String;

class ColumnCommonProps {
  final int? dims;
  final bool? notNull;
  const ColumnCommonProps({this.dims, this.notNull});
}

class RegularColumn extends ColumnCommonProps {
  final String type;
  const RegularColumn({required this.type, super.dims, super.notNull});
}

class VarcharColumn extends ColumnCommonProps {
  final String type; // 'varchar'
  final int? maxLength;
  const VarcharColumn({this.maxLength, super.dims, super.notNull}) : type = 'varchar';
}

class BpcharColumn extends ColumnCommonProps {
  final String type; // 'bpchar'
  final int? length;
  const BpcharColumn({this.length, super.dims, super.notNull}) : type = 'bpchar';
}

class TimeColumn extends ColumnCommonProps {
  final String type; // 'time' | 'timetz' | 'timestamp' | 'timestamptz'
  final int? precision;
  const TimeColumn({required this.type, this.precision, super.dims, super.notNull});
}

class IntervalColumn extends ColumnCommonProps {
  final String type; // 'interval'
  final String? fields;
  const IntervalColumn({this.fields, super.dims, super.notNull}) : type = 'interval';
}

class IntervalColumnWithPrecision extends ColumnCommonProps {
  final String type; // 'interval'
  final int? precision; // 0..6
  final String? fields; // 'SECOND'
  const IntervalColumnWithPrecision({this.precision, this.fields, super.dims, super.notNull}) : type = 'interval';
}

class BitColumn extends ColumnCommonProps {
  final String type; // 'bit'
  final int length;
  const BitColumn({required this.length, super.dims, super.notNull}) : type = 'bit';
}

class NumericColumn extends ColumnCommonProps {
  final String type; // 'numeric'
  final int? precision;
  final int? scale;
  const NumericColumn({this.precision, this.scale, super.dims, super.notNull}) : type = 'numeric';
}

typedef ColumnInfo = Map<String, dynamic>; // use dynamic-typed schema entries
typedef Schema = Map<String, ColumnInfo>;

typedef Message = Map<String, dynamic>;
typedef ControlMessage = Map<String, dynamic>;
typedef ChangeMessage = Map<String, dynamic>;


