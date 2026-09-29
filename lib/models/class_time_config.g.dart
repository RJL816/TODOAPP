// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'class_time_config.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetClassTimeConfigCollection on Isar {
  IsarCollection<ClassTimeConfig> get classTimeConfigs => this.collection();
}

const ClassTimeConfigSchema = CollectionSchema(
  name: r'ClassTimeConfig',
  id: 742279677576650486,
  properties: {
    r'endLabel': PropertySchema(
      id: 0,
      name: r'endLabel',
      type: IsarType.string,
    ),
    r'endMinutes': PropertySchema(
      id: 1,
      name: r'endMinutes',
      type: IsarType.long,
    ),
    r'firstPeriod': PropertySchema(
      id: 2,
      name: r'firstPeriod',
      type: IsarType.long,
    ),
    r'lastPeriod': PropertySchema(
      id: 3,
      name: r'lastPeriod',
      type: IsarType.long,
    ),
    r'periodLabel': PropertySchema(
      id: 4,
      name: r'periodLabel',
      type: IsarType.string,
    ),
    r'startLabel': PropertySchema(
      id: 5,
      name: r'startLabel',
      type: IsarType.string,
    ),
    r'startMinutes': PropertySchema(
      id: 6,
      name: r'startMinutes',
      type: IsarType.long,
    ),
    r'timeLabel': PropertySchema(
      id: 7,
      name: r'timeLabel',
      type: IsarType.string,
    )
  },
  estimateSize: _classTimeConfigEstimateSize,
  serialize: _classTimeConfigSerialize,
  deserialize: _classTimeConfigDeserialize,
  deserializeProp: _classTimeConfigDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _classTimeConfigGetId,
  getLinks: _classTimeConfigGetLinks,
  attach: _classTimeConfigAttach,
  version: '3.1.0+1',
);

int _classTimeConfigEstimateSize(
  ClassTimeConfig object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.endLabel.length * 3;
  bytesCount += 3 + object.periodLabel.length * 3;
  bytesCount += 3 + object.startLabel.length * 3;
  bytesCount += 3 + object.timeLabel.length * 3;
  return bytesCount;
}

void _classTimeConfigSerialize(
  ClassTimeConfig object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.endLabel);
  writer.writeLong(offsets[1], object.endMinutes);
  writer.writeLong(offsets[2], object.firstPeriod);
  writer.writeLong(offsets[3], object.lastPeriod);
  writer.writeString(offsets[4], object.periodLabel);
  writer.writeString(offsets[5], object.startLabel);
  writer.writeLong(offsets[6], object.startMinutes);
  writer.writeString(offsets[7], object.timeLabel);
}

ClassTimeConfig _classTimeConfigDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ClassTimeConfig();
  object.endMinutes = reader.readLong(offsets[1]);
  object.firstPeriod = reader.readLong(offsets[2]);
  object.id = id;
  object.lastPeriod = reader.readLong(offsets[3]);
  object.startMinutes = reader.readLong(offsets[6]);
  return object;
}

P _classTimeConfigDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readLong(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _classTimeConfigGetId(ClassTimeConfig object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _classTimeConfigGetLinks(ClassTimeConfig object) {
  return [];
}

void _classTimeConfigAttach(
    IsarCollection<dynamic> col, Id id, ClassTimeConfig object) {
  object.id = id;
}

extension ClassTimeConfigQueryWhereSort
    on QueryBuilder<ClassTimeConfig, ClassTimeConfig, QWhere> {
  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension ClassTimeConfigQueryWhere
    on QueryBuilder<ClassTimeConfig, ClassTimeConfig, QWhereClause> {
  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ClassTimeConfigQueryFilter
    on QueryBuilder<ClassTimeConfig, ClassTimeConfig, QFilterCondition> {
  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endLabelEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endLabelGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'endLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endLabelLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'endLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endLabelBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'endLabel',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endLabelStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'endLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endLabelEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'endLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endLabelContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'endLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endLabelMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'endLabel',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endLabelIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endLabel',
        value: '',
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endLabelIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'endLabel',
        value: '',
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endMinutesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endMinutesGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'endMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endMinutesLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'endMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      endMinutesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'endMinutes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      firstPeriodEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'firstPeriod',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      firstPeriodGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'firstPeriod',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      firstPeriodLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'firstPeriod',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      firstPeriodBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'firstPeriod',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      lastPeriodEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastPeriod',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      lastPeriodGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastPeriod',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      lastPeriodLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastPeriod',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      lastPeriodBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastPeriod',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      periodLabelEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'periodLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      periodLabelGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'periodLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      periodLabelLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'periodLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      periodLabelBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'periodLabel',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      periodLabelStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'periodLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      periodLabelEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'periodLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      periodLabelContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'periodLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      periodLabelMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'periodLabel',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      periodLabelIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'periodLabel',
        value: '',
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      periodLabelIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'periodLabel',
        value: '',
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startLabelEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startLabelGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'startLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startLabelLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'startLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startLabelBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'startLabel',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startLabelStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'startLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startLabelEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'startLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startLabelContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'startLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startLabelMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'startLabel',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startLabelIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startLabel',
        value: '',
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startLabelIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'startLabel',
        value: '',
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startMinutesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startMinutesGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'startMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startMinutesLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'startMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      startMinutesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'startMinutes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      timeLabelEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'timeLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      timeLabelGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'timeLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      timeLabelLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'timeLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      timeLabelBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'timeLabel',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      timeLabelStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'timeLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      timeLabelEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'timeLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      timeLabelContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'timeLabel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      timeLabelMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'timeLabel',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      timeLabelIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'timeLabel',
        value: '',
      ));
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterFilterCondition>
      timeLabelIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'timeLabel',
        value: '',
      ));
    });
  }
}

extension ClassTimeConfigQueryObject
    on QueryBuilder<ClassTimeConfig, ClassTimeConfig, QFilterCondition> {}

extension ClassTimeConfigQueryLinks
    on QueryBuilder<ClassTimeConfig, ClassTimeConfig, QFilterCondition> {}

extension ClassTimeConfigQuerySortBy
    on QueryBuilder<ClassTimeConfig, ClassTimeConfig, QSortBy> {
  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByEndLabel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endLabel', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByEndLabelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endLabel', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByEndMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endMinutes', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByEndMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endMinutes', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByFirstPeriod() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firstPeriod', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByFirstPeriodDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firstPeriod', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByLastPeriod() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastPeriod', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByLastPeriodDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastPeriod', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByPeriodLabel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'periodLabel', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByPeriodLabelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'periodLabel', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByStartLabel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startLabel', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByStartLabelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startLabel', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByStartMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startMinutes', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByStartMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startMinutes', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByTimeLabel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timeLabel', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      sortByTimeLabelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timeLabel', Sort.desc);
    });
  }
}

extension ClassTimeConfigQuerySortThenBy
    on QueryBuilder<ClassTimeConfig, ClassTimeConfig, QSortThenBy> {
  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByEndLabel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endLabel', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByEndLabelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endLabel', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByEndMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endMinutes', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByEndMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endMinutes', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByFirstPeriod() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firstPeriod', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByFirstPeriodDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firstPeriod', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByLastPeriod() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastPeriod', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByLastPeriodDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastPeriod', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByPeriodLabel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'periodLabel', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByPeriodLabelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'periodLabel', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByStartLabel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startLabel', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByStartLabelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startLabel', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByStartMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startMinutes', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByStartMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startMinutes', Sort.desc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByTimeLabel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timeLabel', Sort.asc);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QAfterSortBy>
      thenByTimeLabelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timeLabel', Sort.desc);
    });
  }
}

extension ClassTimeConfigQueryWhereDistinct
    on QueryBuilder<ClassTimeConfig, ClassTimeConfig, QDistinct> {
  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QDistinct> distinctByEndLabel(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'endLabel', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QDistinct>
      distinctByEndMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'endMinutes');
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QDistinct>
      distinctByFirstPeriod() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'firstPeriod');
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QDistinct>
      distinctByLastPeriod() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastPeriod');
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QDistinct>
      distinctByPeriodLabel({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'periodLabel', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QDistinct>
      distinctByStartLabel({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'startLabel', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QDistinct>
      distinctByStartMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'startMinutes');
    });
  }

  QueryBuilder<ClassTimeConfig, ClassTimeConfig, QDistinct> distinctByTimeLabel(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'timeLabel', caseSensitive: caseSensitive);
    });
  }
}

extension ClassTimeConfigQueryProperty
    on QueryBuilder<ClassTimeConfig, ClassTimeConfig, QQueryProperty> {
  QueryBuilder<ClassTimeConfig, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<ClassTimeConfig, String, QQueryOperations> endLabelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'endLabel');
    });
  }

  QueryBuilder<ClassTimeConfig, int, QQueryOperations> endMinutesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'endMinutes');
    });
  }

  QueryBuilder<ClassTimeConfig, int, QQueryOperations> firstPeriodProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'firstPeriod');
    });
  }

  QueryBuilder<ClassTimeConfig, int, QQueryOperations> lastPeriodProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastPeriod');
    });
  }

  QueryBuilder<ClassTimeConfig, String, QQueryOperations>
      periodLabelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'periodLabel');
    });
  }

  QueryBuilder<ClassTimeConfig, String, QQueryOperations> startLabelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'startLabel');
    });
  }

  QueryBuilder<ClassTimeConfig, int, QQueryOperations> startMinutesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'startMinutes');
    });
  }

  QueryBuilder<ClassTimeConfig, String, QQueryOperations> timeLabelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'timeLabel');
    });
  }
}
