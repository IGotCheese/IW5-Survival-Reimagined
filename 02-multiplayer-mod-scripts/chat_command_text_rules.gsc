#include scripts\chat_commands;

Init()
{
    CreateCommand(level.chat_commands["ports"], "rules", "text", ["^3== Your Server Rules ==", "^71. No cheating, hacking or exploiting", "^72. Respect others - no racism or harassment", "^73. Do not ruin the game for everyone else", "^2Have fun!  -  yourserver.gg"], 1);
}