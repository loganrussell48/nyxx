part of nyxx.commands;

class _CommandMetadata {
  MethodMirror method;
  ObjectMirror parent;

  Command methodCommand;

  Restrict restrict;

  List<Preprocessor> preprocessors;
  List<Postprocessor> postprocessors;

  List<String> commandString;

  _CommandMetadata(this.commandString, this.method, this.parent,
      this.methodCommand, this.restrict,
      [this.preprocessors = const [], this.postprocessors = const []]);

  static String helpMessage(_CommandMetadata _commandMetadata){
    var methodCommand = _commandMetadata.methodCommand;
    var name = '**Name**:\t${methodCommand.name}\n';
    var aliases = '**Aliases**:\t'+[for(var alias in methodCommand.aliases) alias].join(' ')+'\n';
    var restrict = '**Restrictions**:\t'+_commandMetadata.restrict.toString()+'\n';

    return name+aliases+restrict;
  }
}
