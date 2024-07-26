local LibDialog = LibStub("LibDialog-1.1")

LibDialog:Register("RCWOWAUDIT_OUTDATED_MESSAGE", {
  text = "Your version of RCLootCouncil is probably too old to work with this version of the wowaudit module. Please update it!",
	icon = "",
  buttons = {
		{
			text = _G.OKAY,
		}
	},
  show_while_dead = true,
  hide_on_escape = true,
})
