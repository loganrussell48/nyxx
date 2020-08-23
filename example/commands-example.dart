import 'dart:math';

import 'package:nyxx/Vm.dart';
import 'package:nyxx/commands.dart';

import 'dart:io';
import 'dart:async';


extension prob on num {
  bool get chance => this <= 0 ? false : this >= 100 ? true : Random().nextInt(100) <= this;
}

var buttifyProbability = 15;
CommandsFramework cf;
var _prefix = '?';
const POWER_OFF_ROLE = Snowflake.of('475160669654614026');
Nyxx bot;
File f = File('admins.txt');
var admins = <Snowflake>{};

// Main function
void main() {
  // Create new bot instance
  // Dart 2 introduces optional new keyword, so we can leave it
  bot = NyxxVm(Platform.environment['DISCORD_TOKEN']);

  loadSavedAdmins();
  printCurrentAdmins();
  // Creating new CommandsFramework object and registering commands.
  cf = CommandsFramework(bot, prefix: _prefix, admins: admins)
    ..discoverCommands()
    ..onError.listen(onError);

  bot.onReady.listen((event) {
    print("Ready!");
  });

  bot.onMessageReceived.listen((e) {
    var m = e.message;
    var c = m.channel;
    print(m.content);
    print(m.author.id);
    if(m.author.id != Snowflake('746873067170431047')){
      if(!m.content.startsWith(_prefix)){
        if(buttifyProbability.chance) {
          print('Buttifying the message...');
          c.send(content: buttify(m.content.split(' ')));
        }
      }
    }
  });
}

void printCurrentAdmins() {
  print('====Current admins====');
  admins.forEach((admin) {
    print(admin);
  });
}

void onError(CommandExecutionError error){
  switch(error.type){
    case ExecutionErrorType.adminOnly:
      error.message.channel.send(content: '${error.message.author.mention} - You need to be an admin to use that command');
      break;
    default:
      error.message.channel.send(content: "An error occurred: ErrorType: *${error.type}* Error: *${error.exception}* AdditionalInfo: *${error.additionalInfo}*");
  }
}

String buttify(List<String> tokens){
  int words2buttify = tokens.length~/3;
  if(words2buttify==0) words2buttify++;
  var indices = Set<int>();
  var r = Random();
  while(indices.length != words2buttify){
    indices.add(r.nextInt(tokens.length));
  }
  var resList = <String>[];
  for(int i = 0; i < tokens.length; i++){
    var string = tokens[i];
    if(indices.contains(i)){
      //buttify the string
      if(string.length <= 4) string = 'butt';
      else string = 'butt' + string.substring(4);
    }
    resList.add(string);
  }
  return resList.join(' ');
}

/// Example command preprocessor.
class IsGuildProcessor implements Preprocessor {
  const IsGuildProcessor();

  @override
  Future<PreprocessorResult> execute(
      List<Object> services, Message message) async {
    return message.guild != null
        ? PreprocessorResult.success()
        : PreprocessorResult.error("ERROR");
  }
}

class PreLog implements Preprocessor {
  const PreLog();

  @override
  Future<PreprocessorResult> execute(List<Object> services, Message message) async {
    print('=====${message.content}=====');
    return message.guild != null
        ? PreprocessorResult.success()
        : PreprocessorResult.error("ERROR");
  }

}

class PrintString implements Postprocessor {
  final dynamic str;
  const PrintString(this.str);

  @override
  Future<void> execute(List<Object> services, returns, Message message) async {
    print("From postProcessor: $str");
  }
}

@Command("PING")
Future<void> single(CommandContext context) async {
  await context.reply(content: "PONG");
}

@Command("peen")
Future<void> peen(CommandContext context) async {
  await context.reply(content: "PENIS");
}

@Command(Commands.modButtifyProbLong, aliases: [Commands.modButtifyProbShort])
@Restrict(admin: true)
Future<void> modButtProb(CommandContext context) async {
  var tokens = context.message.content.split(' ');
  if(tokens.length <= 1) await context.reply(content: 'You need to specify a probability in the range 0 - 100 for *buttifying* messages');
  if(tokens.length > 2) await context.reply(content: 'Invalid Syntax.\nProper Syntax: $_prefix${Commands.modButtifyProbLong} <prob: integer>\nCommand alias: ${Commands.modButtifyProbShort}');
  var probString = tokens[1];
  try{
    var prob = int.parse(probString);
    buttifyProbability = prob;
    await context.reply(content: 'New Buttification Probability: $buttifyProbability%');
  } on Exception {
    await context.reply(content: 'Unable to parse 2nd token to int. Make sure you entered a valid integer value. Likely needs to be in the range [${1<<63} - ${~(1<<63)}]');
  }
}

@Command(Commands.getButtifyProbLong, aliases: [Commands.getButtifyProbShort])
@Restrict(admin: true)
Future<void> getButtProb(CommandContext context) async {
  await context.reply(content: 'Current buttification probability: $buttifyProbability%');
}

@Command(Commands.addAdminLong, aliases: [Commands.addAdminShort])
@Restrict(admin: true)
Future<void> addAdmin(CommandContext context) async {
  var tokens = context.message.content.split(' ');
  if(tokens.length != 2)
    await context.reply(content: 'Invalid syntax. Must be exactly 2 tokens. 1. ${_prefix}${Commands.addAdminLong} 2. <id> (NOT username)\nCommand alias: ${Commands.addAdminShort}');
  else{
    var id = tokens.elementAt(1);
    cf.addAdmin(Snowflake(id));
    await context.reply(content: 'Added <@!$id> as an admin');
  }
}

@Command(Commands.shutdownLong, aliases: [Commands.shutdownShort])
@Restrict(roles: [POWER_OFF_ROLE])
Future<void> shutDown(CommandContext context) async {
  await context.reply(content: 'Shutting down...');
  saveCurrentAdmins();
  bot.close();
  bot.dispose();

}

void saveCurrentAdmins() {
  f.deleteSync();
  f.createSync();
  f.writeAsStringSync(admins.map((e) => e.id).join('\n'));
}

void loadSavedAdmins(){
  if(!f.existsSync()){
    f.createSync();
    f.writeAsStringSync('173667235221602304\n'); //always add me as admin :)
  }
  admins = f.readAsLinesSync().map((id) => Snowflake(id)).toSet();
}


class Commands {
  static const String addAdminLong = 'add-admin';
  static const String addAdminShort = 'a-a';
  static const String getButtifyProbLong = 'getButtifyProb';
  static const String getButtifyProbShort = 'gbp';
  static const String modButtifyProbLong = 'modButtifyProb';
  static const String modButtifyProbShort = 'mbp';
  static const String shutdownLong = 'shutdown';
  static const String shutdownShort = 'sd';
}