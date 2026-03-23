ok, so it receive the command and was able to do it but the output is not clean, and also then we need to fix UI.

terminal chat:

You are running inside Toad, a terminal UI with side panels. You can control panels with the /panel command:

•  /panel github — open the GitHub panel (issues, PRs, project state)
•  /panel github close — close it
•  /panel list — list available panels
When the user asks about project state or wants to see issues/PRs, open the GitHub panel with /panel github.

❯
show me the project state

I'll open the GitHub panel so you can see the project state.
▶ 🔧 Skill ▌failed▐

<tool_use_error>Unknown skill: panel</tool_use_error>
The /panel command isn't available as a skill — it's a built-in Toad UI command. You can run it directly in your terminal:


That will open the GitHub panel showing issues, PRs, and project state.
To see what panels are available:

end of terminal chat.

github structure notes:
1. we want to see timeline like, so that is like issues, pending, closed overview with count. dropdown details. the issues are the plans there is no extra plans tab. and the pr is fine, the commits should be the collapse option and the table the extended first view.
can we make the "split" size different? because in this case the github one does benefit from wider view. also the chat is not so wide and is wasting space.