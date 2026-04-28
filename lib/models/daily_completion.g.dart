// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_completion.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetDailyCompletionCollection on Isar {
  IsarCollection<DailyCompletion> get dailyCompletions => this.collection();
}

const DailyCompletionSchema = CollectionSchema(
  name: r'DailyCompletion',
  id: -8413370184331475747,
  properties: {
    r'date': PropertySchema(
      id: 0,
      name: r'date',
      type: IsarType.dateTime,
    ),
    r'timestamp': PropertySchema(
      id: 1,
      name: r'timestamp',
      type: IsarType.long,
    ),
    r'todoId': PropertySchema(
      id: 2,
      name: r'todoId',
      type: IsarType.long,
    )
  },
  estimateSize: _dailyCompletionEstimateSize,
  serialize: _dailyCompletionSerialize,
  deserialize: _dailyCompletionDeserialize,
  deserializeProp: _dailyCompletionDeserializeProp,
  idName: r'id',
  indexes: {
    r'todoId': IndexSchema(
      id: 4266691497494727738,
      name: r'todoId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'todoId',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'date': IndexSchema(
      id: -7552997827385218417,
      name: r'date',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'date',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _dailyCompletionGetId,
  getLinks: _dailyCompletionGetLinks,
  attach: _dailyCompletionAttach,
  version: '3.1.0+1',
);

int _dailyCompletionEstimateSize(
  DailyCompletion object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  return bytesCount;
}

void _dailyCompletionSerialize(
  DailyCompletion object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.date);
  writer.writeLong(offsets[1], object.timestamp);
  writer.writeLong(offsets[2], object.todoId);
}

DailyCompletion _dailyCompletionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = DailyCompletion();
  object.date = reader.readDateTime(offsets[0]);
  object.id = id;
  object.timestamp = reader.readLong(offsets[1]);
  object.todoId = reader.readLong(offsets[2]);
  return object;
}

P _dailyCompletionDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _dailyCompletionGetId(DailyCompletion object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _dailyCompletionGetLinks(DailyCompletion object) {
  return [];
}

void _dailyCompletionAttach(
    IsarCollection<dynamic> col, Id id, DailyCompletion object) {
  object.id = id;
}

extension DailyCompletionQueryWhereSort
    on QueryBuilder<DailyCompletion, DailyCompletion, QWhere> {
  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhere> anyTodoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'todoId'),
      );
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhere> anyDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'date'),
      );
    });
  }
}

extension DailyCompletionQueryWhere
    on QueryBuilder<DailyCompletion, DailyCompletion, QWhereClause> {
  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause>
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

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause> idBetween(
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

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause>
      todoIdEqualTo(int todoId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'todoId',
        value: [todoId],
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause>
      todoIdNotEqualTo(int todoId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'todoId',
              lower: [],
              upper: [todoId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'todoId',
              lower: [todoId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'todoId',
              lower: [todoId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'todoId',
              lower: [],
              upper: [todoId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause>
      todoIdGreaterThan(
    int todoId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'todoId',
        lower: [todoId],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause>
      todoIdLessThan(
    int todoId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'todoId',
        lower: [],
        upper: [todoId],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause>
      todoIdBetween(
    int lowerTodoId,
    int upperTodoId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'todoId',
        lower: [lowerTodoId],
        includeLower: includeLower,
        upper: [upperTodoId],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause> dateEqualTo(
      DateTime date) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'date',
        value: [date],
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause>
      dateNotEqualTo(DateTime date) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [],
              upper: [date],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [date],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [date],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [],
              upper: [date],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause>
      dateGreaterThan(
    DateTime date, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'date',
        lower: [date],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause>
      dateLessThan(
    DateTime date, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'date',
        lower: [],
        upper: [date],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterWhereClause> dateBetween(
    DateTime lowerDate,
    DateTime upperDate, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'date',
        lower: [lowerDate],
        includeLower: includeLower,
        upper: [upperDate],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension DailyCompletionQueryFilter
    on QueryBuilder<DailyCompletion, DailyCompletion, QFilterCondition> {
  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      dateEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'date',
        value: value,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      dateGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'date',
        value: value,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      dateLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'date',
        value: value,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      dateBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'date',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
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

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
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

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
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

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      timestampEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      timestampGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      timestampLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      timestampBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'timestamp',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      todoIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'todoId',
        value: value,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      todoIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'todoId',
        value: value,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      todoIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'todoId',
        value: value,
      ));
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterFilterCondition>
      todoIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'todoId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension DailyCompletionQueryObject
    on QueryBuilder<DailyCompletion, DailyCompletion, QFilterCondition> {}

extension DailyCompletionQueryLinks
    on QueryBuilder<DailyCompletion, DailyCompletion, QFilterCondition> {}

extension DailyCompletionQuerySortBy
    on QueryBuilder<DailyCompletion, DailyCompletion, QSortBy> {
  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy> sortByDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.asc);
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy>
      sortByDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.desc);
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy>
      sortByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy>
      sortByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy> sortByTodoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoId', Sort.asc);
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy>
      sortByTodoIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoId', Sort.desc);
    });
  }
}

extension DailyCompletionQuerySortThenBy
    on QueryBuilder<DailyCompletion, DailyCompletion, QSortThenBy> {
  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy> thenByDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.asc);
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy>
      thenByDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.desc);
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy>
      thenByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy>
      thenByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy> thenByTodoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoId', Sort.asc);
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QAfterSortBy>
      thenByTodoIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoId', Sort.desc);
    });
  }
}

extension DailyCompletionQueryWhereDistinct
    on QueryBuilder<DailyCompletion, DailyCompletion, QDistinct> {
  QueryBuilder<DailyCompletion, DailyCompletion, QDistinct> distinctByDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'date');
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QDistinct>
      distinctByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'timestamp');
    });
  }

  QueryBuilder<DailyCompletion, DailyCompletion, QDistinct> distinctByTodoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'todoId');
    });
  }
}

extension DailyCompletionQueryProperty
    on QueryBuilder<DailyCompletion, DailyCompletion, QQueryProperty> {
  QueryBuilder<DailyCompletion, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<DailyCompletion, DateTime, QQueryOperations> dateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'date');
    });
  }

  QueryBuilder<DailyCompletion, int, QQueryOperations> timestampProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'timestamp');
    });
  }

  QueryBuilder<DailyCompletion, int, QQueryOperations> todoIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'todoId');
    });
  }
}
