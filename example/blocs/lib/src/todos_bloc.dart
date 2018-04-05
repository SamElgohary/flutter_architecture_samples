// Copyright 2018 The Flutter Architecture Sample Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.

import 'dart:async';

import 'package:blocs/src/models/models.dart';
import 'package:rxdart/rxdart.dart';
import 'package:todos_repository/todos_repository.dart';

class TodosBloc {
  // Inputs
  final Sink<Todo> addTodo;
  final Sink<Todo> updateTodo;
  final Sink<String> deleteTodo;
  final Sink<VisibilityFilter> updateFilter;
  final Sink<void> clearCompleted;
  final Sink<void> toggleAll;

  // Outputs
  final Stream<VisibilityFilter> activeFilter;
  final Stream<bool> allComplete;
  final Stream<bool> hasCompletedTodos;
  final Stream<List<Todo>> visibleTodos;
  final Stream<int> numComplete;
  final Stream<int> numActive;

  factory TodosBloc(ReactiveTodosRepository repository) {
    // We'll use a series of StreamControllers to glue together our inputs and
    // outputs.
    //
    // StreamControllers have both a Sink and a Stream. We'll expose the Sinks
    // publicly so users can send information to the Bloc. We'll use the Streams
    // internally to react to that user input.
    final addTodoController = new StreamController<Todo>(sync: true);
    final clearCompletedController = new PublishSubject<void>(sync: true);
    final removeTodoController = new StreamController<String>(sync: true);
    final toggleAllController = new PublishSubject<void>(sync: true);
    final updateTodoController = new StreamController<Todo>(sync: true);
    final updateFilterController = new BehaviorSubject<VisibilityFilter>(
      seedValue: VisibilityFilter.all,
      sync: true,
    );

    // A Stream of all Todos from our Repository
    final todos = repository
        .todos()
        .map((entities) => entities.map(Todo.fromEntity).toList());

    // When a user adds an item, add it to the repository
    addTodoController.stream
        .listen((todo) => repository.addNewTodo(todo.toEntity()));

    // When a user updates an item, update the repository
    updateTodoController.stream
        .listen((todo) => repository.updateTodo(todo.toEntity()));

    // When a user removes an item, remove it from the repository
    removeTodoController.stream.listen((id) => repository.deleteTodo([id]));

    // When a user clears the completed items, convert the current list of todos
    // into a list of ids, then send that to the repository
    clearCompletedController.stream
        .switchMap<List<String>>((_) => todos.map(_completedTodoIds).take(1))
        .listen((ids) {
      return repository.deleteTodo(ids);
    });

    // When a user toggles all todos, calculate whether all todos should be
    // marked complete or incomplete and push the change to the repository
    toggleAllController.stream
        .switchMap<List<Todo>>((_) => todos.map(_todosToUpdate).take(1))
        .listen((updates) => updates
            .forEach((update) => repository.updateTodo(update.toEntity())));

    // To calculate the visible todos, we combine the todos with the current
    // visibility filter and return the filtered todos.
    //
    // Every time the todos or the filter changes the visible items will emit
    // once again.
    final visibleTodosController = new BehaviorSubject<List<Todo>>();

    Observable
        .combineLatest2<List<Todo>, VisibilityFilter, List<Todo>>(
            todos, updateFilterController.stream, _filterTodos)
        .pipe(visibleTodosController);

    // Calculate whether or not all todos are complete
    final allComplete = todos.map(_allComplete);

    // Calculate whether or not all todos are complete
    final hasCompletedTodos = todos.map(_hasCompletedTodos);

    return new TodosBloc._(
      addTodoController,
      updateTodoController,
      removeTodoController,
      updateFilterController,
      clearCompletedController,
      toggleAllController,
      visibleTodosController.stream,
      allComplete,
      hasCompletedTodos,
      updateFilterController.stream,
      todos.map(_numActive),
      todos.map(_numComplete),
    );
  }

  TodosBloc._(
    this.addTodo,
    this.updateTodo,
    this.deleteTodo,
    this.updateFilter,
    this.clearCompleted,
    this.toggleAll,
    this.visibleTodos,
    this.allComplete,
    this.hasCompletedTodos,
    this.activeFilter,
    this.numActive,
    this.numComplete,
  );

  static bool _allComplete(List<Todo> todos) =>
      todos.every((todo) => todo.complete);

  static List<String> _completedTodoIds(List<Todo> todos) {
    return todos.fold<List<String>>([], (prev, todo) {
      if (todo.complete) {
        return prev..add(todo.id);
      } else {
        return prev;
      }
    });
  }

  static List<Todo> _filterTodos(List<Todo> todos, VisibilityFilter filter) {
    return todos.where((todo) {
      switch (filter) {
        case VisibilityFilter.all:
          return true;
        case VisibilityFilter.active:
          return !todo.complete;
        case VisibilityFilter.completed:
          return todo.complete;
      }
    }).toList();
  }

  static List<Todo> _todosToUpdate(List<Todo> todos) {
    final allComplete = _allComplete(todos);

    return todos.fold<List<Todo>>([], (prev, todo) {
      if (allComplete) {
        return prev..add(todo.copyWith(complete: false));
      } else if (!allComplete && !todo.complete) {
        return prev..add(todo.copyWith(complete: true));
      } else {
        return prev;
      }
    });
  }

  static bool _hasCompletedTodos(List<Todo> todos) {
    return todos.any((todo) => todo.complete);
  }

  static int _numComplete(List<Todo> todos) {
    return todos.fold(0, (sum, todo) => todo.complete ? ++sum : sum);
  }

  static int _numActive(List<Todo> todos) {
    return todos.fold(0, (sum, todo) => !todo.complete ? ++sum : sum);
  }
}