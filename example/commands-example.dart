import 'dart:math';

import 'package:nyxx/Vm.dart';
import 'package:nyxx/commands.dart';

import 'dart:io';
import 'dart:async';

extension prob on num {
  bool get chance =>
      this <= 0 ? false : this >= 100 ? true : Random().nextInt(100) <= this;
}

extension altcaps on String {
  String get altCaps {
    return [
      for (int i = 0; i < length; i++)
        i.isEven
            ? substring(i, i + 1).toUpperCase()
            : substring(i, i + 1).toLowerCase()
    ].join();
  }
}

var buttifyProbability = 15;
var mockProbability = 15;
CommandsFramework cf;
var _prefix = '?';
const POWER_OFF_ROLE = Snowflake.of('475160669654614026');
Nyxx bot;
File f = File('admins.txt');
File mockUsers = File('mockUsers.txt');

var admins = <Snowflake>{};
var usersToMock = <Snowflake>{};
// Main function
void main() {
  // Create new bot instance
  // Dart 2 introduces optional new keyword, so we can leave it
  bot = NyxxVm(Platform.environment['DISCORD_TOKEN']);

  loadSavedAdmins();
  printCurrentAdmins();

  loadMockUsers();
  printMockUsers();

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
    if(!isCommand(m)){
      if (usersToMock.contains(m.author.id)) {
        if(mockProbability.chance) {
          var mockedMessage = m.content.altCaps;
          if(mockedMessage != m.content){
            c.send(content: m.content.altCaps);
          }
        }
      }
      else if (m.author.id != bot.self.id) {
        print(m.content);
        print(m.author.id);
        if (!m.content.startsWith(_prefix)) {
          if (buttifyProbability.chance) {
            print('Buttifying the message...');
            c.send(content: buttify(m.content.split(' ')));
          }
        }
      }
    }
  });
}

bool isCommand(Message m) {
  return m?.content?.startsWith(_prefix) ?? false;
}

void printMockUsers() {
  print('====Users to Mock====');
  usersToMock.forEach((user) {
    print(user);
  });
}

void loadMockUsers() {
  if (!mockUsers.existsSync()) {
    mockUsers.createSync();
  }
  usersToMock = mockUsers.readAsLinesSync().map((id) => Snowflake(id)).toSet();
}

void saveMockUser() {
  mockUsers.deleteSync();
  mockUsers.createSync();
  mockUsers.writeAsStringSync(usersToMock.map((e) => e.id).join('\n'));
}

void printCurrentAdmins() {
  print('====Current admins====');
  admins.forEach((admin) {
    print(admin);
  });
}

void onError(CommandExecutionError error) {
  switch (error.type) {
    case ExecutionErrorType.adminOnly:
      error.message.channel.send(
          content:
              '${error.message.author.mention} - You need to be an admin to use that command');
      break;
    default:
      error.message.channel.send(
          content:
              "An error occurred: ErrorType: *${error.type}* Error: *${error.exception}* AdditionalInfo: *${error.additionalInfo}*");
  }
}

String buttify(List<String> tokens) {
  int words2buttify = tokens.length ~/ 3;
  if (words2buttify == 0) words2buttify++;
  var indices = Set<int>();
  var r = Random();
  while (indices.length != words2buttify) {
    indices.add(r.nextInt(tokens.length));
  }
  var resList = <String>[];
  for (int i = 0; i < tokens.length; i++) {
    var string = tokens[i];
    if (indices.contains(i)) {
      //buttify the string
      if (string.length <= 4)
        string = 'butt';
      else
        string = 'butt' + string.substring(4);
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
  Future<PreprocessorResult> execute(
      List<Object> services, Message message) async {
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

@Command(Commands.peenLong, aliases: [Commands.peenShort])
Future<void> peen(CommandContext context) async {
  await context.reply(content: "PENIS");
}

@Command(Commands.changeButtProbLong, aliases: [Commands.changeButtProbShort])
@Restrict(admin: true)
Future<void> modButtProb(CommandContext context) async {
  var tokens = context.message.content.split(' ');
  if (tokens.length <= 1)
    await context.reply(
        content:
            'You need to specify a probability in the range 0 - 100 for *buttifying* messages');
  if (tokens.length > 2)
    await context.reply(
        content:
            'Invalid Syntax.\nProper Syntax: $_prefix${Commands.changeButtProbLong} <prob: integer>\nCommand alias: ${Commands.changeButtProbShort}');
  var probString = tokens[1];
  try {
    var prob = int.parse(probString);
    buttifyProbability = prob;
    await context.reply(
        content: 'New Buttification Probability: $buttifyProbability%');
  } on Exception {
    await context.reply(
        content:
            'Unable to parse 2nd token to int. Make sure you entered a valid integer value. Likely needs to be in the range [${1 << 63} - ${~(1 << 63)}]');
  }
}

@Command(Commands.getButtifyProbLong, aliases: [Commands.getButtifyProbShort])
@Restrict(admin: true)
Future<void> getButtProb(CommandContext context) async {
  await context.reply(
      content: 'Current buttification probability: $buttifyProbability%');
}

@Command(Commands.addAdminLong, aliases: [Commands.addAdminShort])
@Restrict(admin: true)
Future<void> addAdmin(CommandContext context, User user) async {
  if (user == null)
    await context.reply(
        content:
            'Invalid syntax. Must be exactly 2 tokens. 1. ${_prefix}${Commands.addAdminLong} 2. <id> (NOT username)\nCommand alias: ${Commands.addAdminShort}');
  else {
    cf.addAdmin(user.id);
    await context.reply(content: 'Added ${user.mention} as an admin');
  }
}

@Command(Commands.removeAdminLong, aliases: [Commands.removeAdminShort])
Future<void> removeAdmin(CommandContext context, User user) async {
  if (user == null)
    await context.reply(
        content:
            'Invalid syntax. Must be exactly 2 tokens. 1. ${_prefix}${Commands.removeAdminLong} 2. <id> (NOT username)\nCommand alias: ${Commands.removeAdminShort}');
  else {
    var removed = cf.removeAdmin(user.id);
    if (removed)
      await context.reply(content: 'Removed ${user.mention} from admins');
    else
      await context.reply(
          content:
              'User: ${user.mention} was not an admin. No need to remove.');
  }
}

@Command(Commands.shutdownLong, aliases: [Commands.shutdownShort])
@Restrict(admin: true)
Future<void> shutDown(CommandContext context) async {
  await context.reply(content: 'Shutting down...');
  saveCurrentAdmins();
  saveMockUser();
  Future.wait([bot.close(), bot.dispose()]).whenComplete(() => exit(0));
}

@Command('help')
Future<void> help(CommandContext context) async {
  var helpmessage = cf.help();
  print(helpmessage);
  await context.reply(content: helpmessage);
}

void saveCurrentAdmins() {
  f.deleteSync();
  f.createSync();
  f.writeAsStringSync(admins.map((e) => e.id).join('\n'));
}

void loadSavedAdmins() {
  if (!f.existsSync()) {
    f.createSync();
    f.writeAsStringSync('173667235221602304\n'); //always add me as admin :)
  }
  admins = f.readAsLinesSync().map((id) => Snowflake(id)).toSet();
}

@Command(Commands.test)
@Restrict(admin: true)
Future<void> test(
    CommandContext context, User user, String messageContentIHope) async {
  print('MessageContentIHope: $messageContentIHope');
  print(user.username);
  print(user.discriminator);
}

@Command("mock")
@Restrict(admin: true)
Future<void> mock(CommandContext context, User user) async {
  if (user == null)
    await context.reply(
        content:
        'Invalid syntax. Must be exactly 2 tokens. 1. ${_prefix}${Commands.removeAdminLong} 2. <id> (NOT username)\nCommand alias: ${Commands.removeAdminShort}');
  else {
    var added = usersToMock.add(user.id);
    if (added)
      await context.reply(content: '${user.mention} will now be mocked by ${bot.self.mention}');
    else
      await context.reply(
          content:
          'User: ${user.mention} was not added to the mock list. Maybe the\'re already being mocked?');
  }
}

@Command(Commands.kingLong, aliases: [Commands.kingShort])
Future<void> king(CommandContext context) async {
  await context.reply(content: 'https://pbs.twimg.com/media/ESP2r_bUUAAcgTs.jpg');
//  await context.message.delete();
}

@Command(Commands.queenLong, aliases: [Commands.queenShort])
Future<void> queen(CommandContext context) async {
  await context.reply(content: 'https://i.redd.it/8w98s87u8p051.png');
//  await context.message.delete();
}

class Commands {
  static const String addAdminLong = 'add-admin';
  static const String addAdminShort = 'a-a';
  static const String removeAdminLong = 'remove-admin';
  static const String removeAdminShort = 'r-a';
  static const String getButtifyProbLong = 'butt-prob';
  static const String getButtifyProbShort = 'bp';
  static const String changeButtProbLong = 'change-butt-prob';
  static const String changeButtProbShort = 'cbp';
  static const String shutdownLong = 'shutdown';
  static const String shutdownShort = 'sd';
  static const String peenLong = 'peen';
  static const String peenShort = 'p';
  static const String test = 'test';
  static const String kingLong = 'king';
  static const String kingShort = 'k';
  static const String queenLong = 'queen';
  static const String queenShort = 'q';
}
