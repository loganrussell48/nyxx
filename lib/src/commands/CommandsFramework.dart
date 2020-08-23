part of nyxx.commands;

/// Gets single annotation with type [T] from [declaration]
T getCmdAnnot<T>(DeclarationMirror declaration) {
  Iterable<T> fs = getCmdAnnots<T>(declaration);
  if (fs.isEmpty) return null;
  return fs.first;
}

/// Gets all annotations with type [T] from [declaration]
Iterable<T> getCmdAnnots<T>(DeclarationMirror declaration) sync* {
  for (var instance in declaration.metadata)
    if (instance.hasReflectee && instance.reflectee is T)
      yield instance.reflectee as T;
}

/// Main point of commands in nyx.
/// It gets all sent messages and matches to registered command and invokes its action.
class CommandsFramework {
  List<_CommandMetadata> _commands;

  List<TypeConverter> _typeConverters;
  CooldownCache _cooldownCache;
  List<Object> _services = List();

  StreamController<CommandExecutionError> _onError;
  Stream<CommandExecutionError> onError;

  Set<Snowflake> _admins;
  final Logger _logger = Logger("CommandsFramework");

  /// Prefix needed to dispatch a commands.
  /// All messages without this prefix will be ignored
  String prefix;

  Nyxx client;

  /// Creates commands framework handler. Requires prefix to handle commands.
  CommandsFramework(this.client,
      {this.prefix,
      Stream<MessageEvent> stream,
      Duration roundupTime = const Duration(minutes: 2),
      bool ignoreBots = true,
      Set<Snowflake> admins = const <Snowflake>{}}) {
    this._commands = List();
    _cooldownCache = CooldownCache(roundupTime);
    _admins = admins;

    _onError = StreamController.broadcast();
    onError = _onError.stream;

    _typeConverters = List();

    client.onReady.listen((_) {
      if (prefix == null && stream == null) {
        prefix = client.self.mention;
        stream = client.onSelfMention;
      } else if (stream == null && prefix != null)
        stream = client.onMessageReceived;
      else {
        _logger.severe("CANNOT CREATE FRAMEWORK WITHOUT PREFIX");
        exit(1);
      }

      stream.listen((MessageEvent e) {
        if (ignoreBots && e.message.author.bot) return;
        if (!e.message.content.startsWith(prefix)) return;

        Future(() => _dispatch(e));
      });
    });
  }

  bool addAdmin(Snowflake id){
    return _admins.add(id);
  }

  bool removeAdmin(Snowflake id){
    return _admins.remove(id);
  }

  /// Allows to register new converters for custom type
  void registerTypeConverters(List<TypeConverter> converters) =>
      _typeConverters.addAll(converters);

  /// Register services to injected into commands modules. Has to be executed before registering commands.
  /// There cannot be more than 1 dependency with single type. Only first will be injected.
  void registerServices(List<Object> services) =>
      this._services.addAll(services);

  /// Register all services in current isolate. It captures all classes which inherits from [Service] class and performs dependency injection if possible.
  void discoverServices() {
    var superClass = reflectClass(Service);
    var mirrorSystem = currentMirrorSystem();

    mirrorSystem.libraries.forEach((uri, lib) {
      for (var cm in lib.declarations.values) {
        if (cm is ClassMirror) {
          if (cm.isSubclassOf(superClass) && !cm.isAbstract) {
            var toInject = _createConstuctorInjections(cm);

            try {
              var serv = cm.newInstance(Symbol(''), toInject).reflectee;
              _services.add(serv);
            } catch (e) {
              throw Exception(
                  "Service [${util.getSymbolName(cm.simpleName)}] constructor not satisfied!");
            }

            break;
          }
        }
      }
    });
  }

  List<Object> _createConstuctorInjections(ClassMirror service) {
    var ctor = service.declarations.values.toList().firstWhere((m) {
      if (m is MethodMirror) return m.isConstructor;

      return false;
    }) as MethodMirror;

    var params = ctor.parameters;
    var toInject = List<dynamic>();

    for (var param in params) {
      for (var service in _services) {
        if (param.type.reflectedType == service.runtimeType ||
            param.type.isAssignableTo(reflectType(service.runtimeType)))
          toInject.add(service);
      }
    }
    return toInject;
  }

  String _createLog(Command methodCmd) => "[${methodCmd.name}]";

  List<List> _getProcessors(DeclarationMirror methodMirror) {
    var methodPre = getCmdAnnots<Preprocessor>(methodMirror);
    var methodPost = getCmdAnnots<Postprocessor>(methodMirror);

    return [
      List<Preprocessor>.from(methodPre),
      List<Postprocessor>.from(methodPost)
    ];
  }

  /// Register commands in current Isolate's libraries. Basically loads all classes as commands with [CommandContext] superclass.
  /// Performs dependency injection when instantiate commands. And throws [Exception] when there are missing services
  void discoverCommands() {
    var mirrorSystem = currentMirrorSystem();

    mirrorSystem.libraries.forEach((_, library) {
      for (var declaration in library.declarations.values) {
        var commandAnnot = getCmdAnnot<Command>(declaration);

        if (commandAnnot == null) continue;

        if (declaration is MethodMirror) {
          var methodRestrict = getCmdAnnot<Restrict>(declaration);
          var processors = _getProcessors(declaration);

          var meta = _CommandMetadata(
              [commandAnnot.name]..addAll(commandAnnot.aliases),
              declaration,
              library,
              commandAnnot,
              methodRestrict,
              processors.first as List<Preprocessor>,
              processors.last as List<Postprocessor>);

          _commands.add(meta);
        }
      }
    });
    _commands.sort((first, second) =>
        -first.commandString.first.compareTo(second.commandString.first));
    _logger.fine("Registered ${_commands.length} commands");
  }

  /// Dispatches onMessage event to framework.
  Future _dispatch(MessageEvent e) async {
    var cmdWithoutPrefix = e.message.content.replaceFirst(prefix, "").trim();

    _CommandMetadata matchedMeta;
    try {
      matchedMeta = _commands.firstWhere((meta) {
        return meta.commandString
            .any((str) => cmdWithoutPrefix.startsWith(str));
      });
    } on Error {
      _onError.add(
          CommandExecutionError(ExecutionErrorType.commandNotFound, e.message));
      return;
    }

    if (matchedMeta.methodCommand.typing) e.message.channel.startTypingLoop();

    var executionCode = -1;
    executionCode = await checkPermissions(matchedMeta, e.message);

    if (executionCode == -1 && matchedMeta.preprocessors.length > 0) {
      for (var p in matchedMeta.preprocessors) {
        try {
          var res = await p.execute(_services, e.message);

          if (!res.isSuccessful) {
            _onError.add(CommandExecutionError(
                ExecutionErrorType.preprocessorFail,
                e.message,
                res.exception,
                res.message));
            executionCode = 8;
            break;
          }
        } catch (err) {
          _onError.add(CommandExecutionError(
              ExecutionErrorType.preprocessorException,
              e.message,
              err as Exception));
        }
      }
    }

    // Submethod to invoke postprocessors
    void invokePost(res) {
      if (matchedMeta.postprocessors.length > 0) {
        for (var post in matchedMeta.postprocessors)
          Future.microtask(() => post.execute(_services, res, e.message));
      }
    }

    // Switch between execution codes
    switch (executionCode) {
      case 0:
        _onError.add(
            CommandExecutionError(ExecutionErrorType.adminOnly, e.message));
        break;
      case 1:
        _onError.add(CommandExecutionError(
            ExecutionErrorType.userPermissionsError, e.message));
        break;
      case 6:
        _onError.add(CommandExecutionError(
            ExecutionErrorType.botPermissionError, e.message));
        break;
      case 2:
        _onError
            .add(CommandExecutionError(ExecutionErrorType.cooldown, e.message));
        break;
      case 3:
        _onError.add(
            CommandExecutionError(ExecutionErrorType.wrongContext, e.message));
        break;
      case 4:
        _onError.add(
            CommandExecutionError(ExecutionErrorType.nfswAccess, e.message));
        break;
      case 5:
        _onError.add(
            CommandExecutionError(ExecutionErrorType.requiredTopic, e.message));
        break;
      case 7:
        _onError.add(
            CommandExecutionError(ExecutionErrorType.roleRequired, e.message));
        break;
      case 9:
        _onError.add(
            CommandExecutionError(ExecutionErrorType.requiresVoice, e.message));
        break;
      case 8:
        break;
      case -1:
      case -2:
      case 100:
        for (var s in matchedMeta.commandString)
          cmdWithoutPrefix = cmdWithoutPrefix.replaceFirst(s, "").trim();

        var methodInj = await _injectParameters(matchedMeta.method,
            _escapeParameters(cmdWithoutPrefix.split(" ")), e.message);

        (matchedMeta.parent
                .invoke(matchedMeta.method.simpleName, methodInj)
                .reflectee as Future)?.then((r) {
          invokePost(r);
        })?.catchError((Exception err, String stack) {
          invokePost([err, stack]);
          _onError.add(CommandExecutionError(
              ExecutionErrorType.commandFailed, e.message, err, stack));
        });

        if (matchedMeta.methodCommand.typing)
          e.message.channel.stopTypingLoop();

        _logger
            .info("Command ${_createLog(matchedMeta.methodCommand)} executed");

        break;
    }
  }

  Future<int> checkPermissions(_CommandMetadata meta, Message e) async {
    var annot = meta.restrict;
    if (annot == null) return -1;

    // Check if command requires admin
    if (annot.admin) return _isUserAdmin(e.author.id, e.guild) ? 100 : 0;

    // Check for reqired context
    if (annot.requiredContext != null) {
      if (annot.requiredContext == ContextType.dm &&
          !(e.channel is DMChannel || e.channel is GroupDMChannel)) return 3;

      if (annot.requiredContext == ContextType.guild &&
          e.channel is! TextChannel) return 3;
    }

    if (e.guild != null) {
      var member = await e.guild.getMember(e.author);

      if (annot.nsfw && !(e.channel as GuildChannel).nsfw) return 4;

      // Check if user is in any channel
      if (annot.requireVoice && e.guild.voiceStates[member.id] == null)
        return 9;

      // Check if there is need to check user roles
      if (annot.roles.isNotEmpty) {
        var hasRoles =
            member.roles.map((f) => f.id).any((t) => annot.roles.contains(t));

        if (!hasRoles) return 7;
      }

      // Check for channel topics
      if (annot.topics.isNotEmpty && e.channel is TextChannel) {
        var topic = (e.channel as TextChannel).topic;
        var list = topic.split(" ");

        var total = list.any((s) => annot.topics.contains(s));
        if (!total) return 5;
      }

      // Check if user has required permissions
      if (annot.userPermissions.isNotEmpty) {
        var total = (e.channel as TextChannel).effectivePermissions(member);

        if (total == Permissions.empty()) return 1;

        if (total != Permissions.all() || _isUserAdmin(member.id, e.guild)) {
          for (var perm in annot.userPermissions) {
            if (!util.isApplied(perm, total.raw)) {
              return 1;
            }
          }
        }
      }

      // Check if bot has required permissions
      if (annot.botPermissions.isNotEmpty) {
        var self = await e.guild.getMember(client.self);
        var total = (e.channel as TextChannel).effectivePermissions(self);
        if (total == Permissions.empty()) return 6;

        if (total != Permissions.all() || !_isUserAdmin(self.id, e.guild)) {
          for (var perm in annot.userPermissions) {
            if (!util.isApplied(perm, total.raw)) {
              return 6;
            }
          }
        }
      }
    }

    //Check if user is on cooldown
    if (annot.cooldown > 0) if (!(await _cooldownCache.canExecute(
        e.author.id, "${meta.methodCommand.name}", annot.cooldown * 1000)))
      return 2;

    return -1;
  }

  // Groups params into
  List<String> _escapeParameters(List<String> splitted) {
    var tmpList = List<String>();
    var isInto = false;

    var finalList = List<String>();

    for (var item in splitted) {
      if (isInto) {
        tmpList.add(item);
        if (item.contains("\"")) {
          isInto = false;
          finalList.add(tmpList.join(" ").replaceAll("\"", ""));
          tmpList.clear();
        }
        continue;
      }

      if (item.contains("\"") && !isInto) {
        isInto = true;
        tmpList.add(item);
        continue;
      }

      finalList.add(item);
    }

    return finalList;
  }

  RegExp _entityRegex = RegExp(r"<(@|@!|@&|#|a?:(.+):)([0-9]+)>");

  Future<List<Object>> _injectParameters(
      MethodMirror method, List<String> splitted, Message msg) async {
    var params = method.parameters;

    List<Object> collected = List();
    var index = 0;

    Future<bool> parsePrimitives(Type type) async {
      switch (type) {
        case String:
          collected.add(splitted[index]);
          break;
        case num:
          collected.add(num.parse(splitted[index]));
          break;
        case int:
          var d = int.parse(splitted[index]);
          collected.add(d);
          break;
        case double:
          var d = double.parse(splitted[index]);
          collected.add(d);
          break;
        case DateTime:
          var d = DateTime.parse(splitted[index]);
          collected.add(d);
          break;
        case Snowflake:
          var id = _entityRegex.firstMatch(splitted[index]).group(3);
          collected.add(Snowflake(id));
          break;
        case TextChannel:
          var id = _entityRegex.firstMatch(splitted[index]).group(3);
          collected.add(msg.guild.channels[Snowflake(id)]);
          break;
        case VoiceState:
          collected.add((await msg.guild.getMember(msg.author)).voiceState);
          break;
        case VoiceChannel:
          collected
              .add((await msg.guild.getMember(msg.author)).voiceState.channel);
          break;
        case User:
          var id = _entityRegex.firstMatch(splitted[index]).group(3);
          collected.add(client.users[Snowflake(id)]);
          break;
        case Member:
          var id = _entityRegex.firstMatch(splitted[index]).group(3);
          collected.add(msg.guild.members[Snowflake(id)]);
          break;
        case Role:
          var id = _entityRegex.firstMatch(splitted[index]).group(3);
          collected.add(msg.guild.roles[Snowflake(id)]);
          break;
        case GuildEmoji:
          var id = _entityRegex.firstMatch(splitted[index]).group(3);
          collected.add(msg.guild.emojis[Snowflake(id)]);
          break;
        case UnicodeEmoji:
          collected.add(
              util.emojisUnicode[splitted[index]..replaceAll(":", "")] ??
                  UnicodeEmoji(splitted[index]));
          break;
        default:
          return false;
      }

      index++;
      return true;
    }

    for (var e in params) {
      var type = e.type.reflectedType;
      if (type == CommandContext) {
        collected.add(CommandContext._new(
            this.client, msg.channel, msg.author, msg.guild, msg));
        continue;
      }

      if (getCmdAnnot<Remainder>(e) != null) {
        var range = splitted.getRange(index, splitted.length).toList();
        if (type == String) {
          collected.add(range.join(" "));
          break;
        }
        collected.add(range);
        break;
      }

      try {
        if (await parsePrimitives(type)) continue;
      } catch (_) {}

      if (_typeConverters.isNotEmpty) {
        var converter = _typeConverters.firstWhere((t) => t._type == type,
            orElse: () => null);
        if (converter != null) {
          collected.add(await converter.parse(splitted[index], msg));
          continue;
        }
      }

      try {
        collected.add(_services.firstWhere((s) => s.runtimeType == type));
      } catch (_) {
        //collected.add(null);
      }
    }

    return collected;
  }

  bool _isUserAdmin(Snowflake authorId, Guild guild) {
    return guild == null
        ? true
        : _admins.contains(authorId) || guild.owner.id == authorId;
  }

  String help() {
    List<String> commandHelpMessages = _commands.map(_CommandMetadata.helpMessage).toList();
    return commandHelpMessages.join('\n');
  }
}
