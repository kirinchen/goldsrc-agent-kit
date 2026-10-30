/* pj010_gameplay: four small gameplay mods for Counter-Strike 1.6 (AMX Mod X 1.10), one file
 *   G (drop)        -> "Leap" skill with a cooldown bar on the HUD; the weapon is NOT dropped
 *   gp_tower        -> an enemy "main tower" in front of you; destroying it ends the round
 *   gp_sentry       -> a sentry gun that turns and fires at enemies on its own
 *   gp_zombie       -> become a zombie: player model, crowbar hands, 1000 hp (until you respawn)
 *   gp_lang en|tw   -> switch the language of this plugin's texts (same as: setinfo lang tw)
 * every text a player sees comes from data/lang/pj010_gameplay.txt through %L
 */
#include <amxmodx>
#include <cstrike>
#include <fakemeta>
#include <engine>
#include <hamsandwich>
#include <fun>

#define LEAP_CD 4.0
#define ZMODEL "zlab"	// falls back to the vip model when the file is missing
#define ZPATH "models/player/zlab/zlab.mdl"	// + zlabT.mdl if the model keeps its textures in a separate file

new Float:g_next[33];
new bool:g_zombie[33];
new g_tower, g_tower_team, g_tower_parts[4], g_tower_nparts;
new g_exp, g_gibs, g_hud;
new bool:g_have_zmodel;
new g_brush[8];

public plugin_precache()
{
	g_exp = precache_model("sprites/zerogxplode.spr");
	g_gibs = precache_model("models/woodgibs.mdl");
	precache_model("models/sentry.mdl");
	precache_model("models/crystal.mdl");
	precache_model("models/v_crowbar.mdl");
	precache_sound("turret/tu_fire1.wav");
	precache_sound("zombie/claw_miss1.wav");
	g_have_zmodel = bool:file_exists(ZPATH);
	if (g_have_zmodel)
		precache_model(ZPATH);
}

public plugin_init()
{
	register_plugin("PJ-010 gameplay", "1.0", "goldsrc-agent-kit");
	register_dictionary("pj010_gameplay.txt");
	register_clcmd("drop", "cmd_drop");
	register_clcmd("gp_tower", "cmd_tower");
	register_clcmd("gp_sentry", "cmd_sentry");
	register_clcmd("gp_zombie", "cmd_zombie");
	register_clcmd("gp_lang", "cmd_lang");
	register_think("gp_sentry", "think_sentry");
	RegisterHam(Ham_TakeDamage, "info_target", "ham_target_damage");
	RegisterHam(Ham_Killed, "info_target", "ham_target_killed");
	RegisterHam(Ham_Item_Deploy, "weapon_knife", "ham_knife_deploy_post", 1);
	RegisterHam(Ham_Spawn, "player", "ham_player_spawn_post", 1);
	g_hud = CreateHudSyncObj();
	set_task(0.1, "hud_tick", _, _, _, "b");

	// the tower is drawn with the map's own crate: the first func_breakable brush model (e.g. "*33")
	new ent = find_ent_by_class(-1, "func_breakable");
	if (ent)
		entity_get_string(ent, EV_SZ_model, g_brush, charsmax(g_brush));
}

// ---------------------------------------------------------------- G: leap with cooldown
public cmd_drop(id)
{
	if (!is_user_alive(id))
		return PLUGIN_CONTINUE;
	new Float:now = get_gametime();
	if (now < g_next[id])
		return PLUGIN_HANDLED;	// still cooling down; the weapon stays in hand either way
	new Float:vel[3];
	velocity_by_aim(id, 420, vel);
	vel[2] = 360.0;
	set_pev(id, pev_velocity, vel);
	g_next[id] = now + LEAP_CD;
	emit_sound(id, CHAN_VOICE, "zombie/claw_miss1.wav", 1.0, ATTN_NORM, 0, PITCH_NORM);
	return PLUGIN_HANDLED;
}

public hud_tick()
{
	new Float:now = get_gametime();
	for (new id = 1; id <= MaxClients; id++)
	{
		if (!is_user_alive(id) || is_user_bot(id))
			continue;
		new msg[128], left = 0;
		if (now < g_next[id])
		{
			new Float:rest = g_next[id] - now, bars = floatround(rest / LEAP_CD * 20.0, floatround_ceil);
			new bar[24];
			for (new i = 0; i < bars && i < 20; i++)
				bar[i] = '|';
			formatex(msg, charsmax(msg), "%L", id, "GP_LEAP_WAIT", rest, bar);
			left = 1;
		}
		else
			formatex(msg, charsmax(msg), "%L", id, "GP_LEAP_READY");
		if (g_tower && pev_valid(g_tower))
			format(msg, charsmax(msg), "%s^n%L", msg, id, "GP_TOWER_HP", floatround(entity_get_float(g_tower, EV_FL_health)));
		set_hudmessage(left ? 255 : 0, left ? 160 : 255, 0, 0.40, 0.78, 0, 0.0, 0.15, 0.0, 0.0, -1);
		ShowSyncHudMsg(id, g_hud, "%s", msg);
	}
}

// ---------------------------------------------------------------- zombie: model + crowbar hands
public cmd_zombie(id)
{
	if (!is_user_alive(id))
		return PLUGIN_HANDLED;
	g_zombie[id] = true;
	cs_set_user_model(id, g_have_zmodel ? ZMODEL : "vip");
	strip_user_weapons(id);
	give_item(id, "weapon_knife");
	set_user_health(id, 1000);
	client_print(id, print_center, "%L", id, "GP_ZOMBIE_ON");
	return PLUGIN_HANDLED;
}

public ham_knife_deploy_post(knife)
{
	new id = get_pdata_cbase(knife, 41, 4);	// m_pPlayer
	if (id >= 1 && id <= MaxClients && g_zombie[id])
	{
		set_pev(id, pev_viewmodel2, "models/v_crowbar.mdl");
		set_pev(id, pev_weaponmodel2, "");
	}
}

public ham_player_spawn_post(id)
{
	if (is_user_alive(id) && g_zombie[id])
	{
		g_zombie[id] = false;
		cs_reset_user_model(id);
	}
}

// ---------------------------------------------------------------- sentry gun
aim_point(id, Float:dist, Float:out[3])
{
	new Float:org[3], Float:ofs[3], Float:ang[3], Float:fwd[3], Float:end[3];
	pev(id, pev_origin, org);
	pev(id, pev_view_ofs, ofs);
	pev(id, pev_v_angle, ang);
	ang[0] = 0.0;
	engfunc(EngFunc_MakeVectors, ang);
	global_get(glb_v_forward, fwd);
	for (new k = 0; k < 3; k++)
	{
		org[k] += ofs[k];
		end[k] = org[k] + fwd[k] * dist;
	}
	engfunc(EngFunc_TraceLine, org, end, IGNORE_MONSTERS, id, 0);
	get_tr2(0, TR_vecEndPos, out);
	for (new k = 0; k < 2; k++)
		out[k] -= fwd[k] * 32.0;
}

public cmd_sentry(id)
{
	if (!is_user_alive(id))
		return PLUGIN_HANDLED;
	new ent = create_entity("info_target");
	new Float:pos[3];
	aim_point(id, 96.0, pos);
	entity_set_string(ent, EV_SZ_classname, "gp_sentry");
	entity_set_model(ent, "models/sentry.mdl");
	entity_set_size(ent, Float:{-16.0, -16.0, 0.0}, Float:{16.0, 16.0, 48.0});
	entity_set_origin(ent, pos);
	entity_set_int(ent, EV_INT_solid, SOLID_BBOX);
	entity_set_int(ent, EV_INT_movetype, MOVETYPE_TOSS);
	entity_set_float(ent, EV_FL_takedamage, DAMAGE_YES);
	entity_set_float(ent, EV_FL_health, 400.0);
	entity_set_edict(ent, EV_ENT_owner, id);
	entity_set_int(ent, EV_INT_iuser1, _:cs_get_user_team(id));
	entity_set_float(ent, EV_FL_framerate, 1.0);
	entity_set_float(ent, EV_FL_nextthink, get_gametime() + 0.5);
	drop_to_floor(ent);
	client_print(id, print_center, "%L", id, "GP_SENTRY_PLACED");
	return PLUGIN_HANDLED;
}

public think_sentry(ent)
{
	entity_set_float(ent, EV_FL_nextthink, get_gametime() + 0.15);
	new owner = entity_get_edict(ent, EV_ENT_owner), team = entity_get_int(ent, EV_INT_iuser1);
	new Float:eye[3], Float:best = 1500.0, target = 0, Float:tpos[3];
	entity_get_vector(ent, EV_VEC_origin, eye);
	eye[2] += 36.0;
	for (new p = 1; p <= MaxClients; p++)
	{
		if (!is_user_alive(p) || _:cs_get_user_team(p) == team)
			continue;
		new Float:o[3];
		pev(p, pev_origin, o);
		new Float:d = get_distance_f(eye, o);
		if (d >= best)
			continue;
		engfunc(EngFunc_TraceLine, eye, o, DONT_IGNORE_MONSTERS, ent, 0);
		new Float:frac;
		get_tr2(0, TR_flFraction, frac);
		if (get_tr2(0, TR_pHit) != p && frac < 1.0)
			continue;	// a wall in between
		best = d; target = p; tpos = o;
	}
	if (!target)
		return;
	new Float:dir[3], Float:ang[3];
	for (new k = 0; k < 3; k++)
		dir[k] = tpos[k] - eye[k];
	vector_to_angle(dir, ang);
	ang[0] = 0.0;
	entity_set_vector(ent, EV_VEC_angles, ang);
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
	write_byte(TE_TRACER);
	write_coord(floatround(eye[0])); write_coord(floatround(eye[1])); write_coord(floatround(eye[2]));
	write_coord(floatround(tpos[0])); write_coord(floatround(tpos[1])); write_coord(floatround(tpos[2]));
	message_end();
	emit_sound(ent, CHAN_WEAPON, "turret/tu_fire1.wav", 0.6, ATTN_NORM, 0, PITCH_NORM);
	ExecuteHamB(Ham_TakeDamage, target, ent, is_user_connected(owner) ? owner : ent, 9.0, DMG_BULLET);	// kills are credited to the owner
}

// ---------------------------------------------------------------- tower: destroy it to win
public cmd_tower(id)
{
	if (!g_brush[0])
	{
		client_print(id, print_console, "gp_tower: this map has no func_breakable to borrow a crate from");
		return PLUGIN_HANDLED;
	}
	tower_remove();
	new Float:pos[3], Float:down[3];
	aim_point(id, 320.0, pos);
	down = pos; down[2] -= 512.0;
	engfunc(EngFunc_TraceLine, pos, down, IGNORE_MONSTERS, id, 0);	// floor under the aim point
	get_tr2(0, TR_vecEndPos, pos);

	new ent = create_entity("info_target");	// the part that takes damage: an invisible 64x64x220 box
	entity_set_string(ent, EV_SZ_classname, "gp_tower");
	entity_set_model(ent, g_brush);	// a studio model would make bullets test its small hitboxes, not this box
	entity_set_int(ent, EV_INT_rendermode, kRenderTransTexture);
	entity_set_float(ent, EV_FL_renderamt, 0.0);
	entity_set_size(ent, Float:{-32.0, -32.0, 0.0}, Float:{32.0, 32.0, 220.0});
	entity_set_int(ent, EV_INT_solid, SOLID_BBOX);
	entity_set_int(ent, EV_INT_movetype, MOVETYPE_NONE);
	entity_set_float(ent, EV_FL_takedamage, DAMAGE_YES);
	entity_set_float(ent, EV_FL_health, 300.0);
	entity_set_origin(ent, pos);	// set the origin after the solid type, or the box is not linked and bullets pass through
	g_tower = ent;

	// look: three copies of the crate stacked up, a red Xen crystal on top (copies may share one brush model)
	new Float:bmin[3], Float:bmax[3], orig = find_ent_by_model(-1, "func_breakable", g_brush);
	g_tower_nparts = 0;
	for (new i = 0; i < 3; i++)
	{
		new c = create_entity("info_target");
		entity_set_string(c, EV_SZ_classname, "gp_tower_part");
		entity_set_model(c, g_brush);	// brush geometry sits at its world position; origin is an offset
		entity_set_int(c, EV_INT_rendermode, entity_get_int(orig, EV_INT_rendermode));	// copy render keys, or it draws black
		entity_set_float(c, EV_FL_renderamt, entity_get_float(orig, EV_FL_renderamt));
		pev(c, pev_mins, bmin); pev(c, pev_maxs, bmax);
		new Float:o[3];
		o[0] = pos[0] - (bmin[0] + bmax[0]) / 2.0;
		o[1] = pos[1] - (bmin[1] + bmax[1]) / 2.0;
		o[2] = pos[2] - bmin[2] + float(i) * (bmax[2] - bmin[2]);
		entity_set_origin(c, o);
		g_tower_parts[g_tower_nparts++] = c;
	}
	new k = create_entity("info_target");
	entity_set_string(k, EV_SZ_classname, "gp_tower_part");
	entity_set_model(k, "models/crystal.mdl");
	new Float:top[3];
	top = pos; top[2] += 3.0 * (bmax[2] - bmin[2]);
	entity_set_origin(k, top);
	entity_set_int(k, EV_INT_renderfx, kRenderFxGlowShell);
	entity_set_vector(k, EV_VEC_rendercolor, Float:{255.0, 0.0, 0.0});
	entity_set_float(k, EV_FL_renderamt, 10.0);
	entity_set_float(k, EV_FL_framerate, 1.0);
	g_tower_parts[g_tower_nparts++] = k;

	g_tower_team = _:CS_TEAM_T;	// the enemy owns it
	if (cs_get_user_team(id) == CS_TEAM_T)
		g_tower_team = _:CS_TEAM_CT;
	return PLUGIN_HANDLED;
}

tower_remove()
{
	if (g_tower && pev_valid(g_tower))
		remove_entity(g_tower);
	for (new i = 0; i < g_tower_nparts; i++)
		if (pev_valid(g_tower_parts[i]))
			remove_entity(g_tower_parts[i]);
	g_tower = 0;
	g_tower_nparts = 0;
}

public ham_target_damage(ent, inflictor, attacker, Float:dmg, bits)
{
	if (ent == g_tower && attacker >= 1 && attacker <= MaxClients && _:cs_get_user_team(attacker) == g_tower_team)
		return HAM_SUPERCEDE;	// defenders cannot hurt their own tower
	return HAM_IGNORED;
}

public ham_target_killed(ent, attacker, gib)
{
	if (ent != g_tower)
		return HAM_IGNORED;
	new Float:o[3];
	entity_get_vector(ent, EV_VEC_origin, o);
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
	write_byte(TE_EXPLOSION);
	write_coord(floatround(o[0])); write_coord(floatround(o[1])); write_coord(floatround(o[2]));
	write_short(g_exp); write_byte(40); write_byte(15); write_byte(0);
	message_end();
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY);	// crate gibs
	write_byte(TE_BREAKMODEL);
	write_coord(floatround(o[0])); write_coord(floatround(o[1])); write_coord(floatround(o[2]) + 100);
	write_coord(64); write_coord(64); write_coord(200);
	write_coord(0); write_coord(0); write_coord(30);
	write_byte(20); write_short(g_gibs); write_byte(30); write_byte(40); write_byte(0x08);
	message_end();
	for (new i = 0; i < g_tower_nparts; i++)
		if (pev_valid(g_tower_parts[i]))
			remove_entity(g_tower_parts[i]);
	g_tower_nparts = 0;
	set_task(0.1, "tower_gone", ent);	// not inside its own Killed call
	g_tower = 0;
	set_hudmessage(255, 60, 0, -1.0, 0.3, 0, 0.0, 4.0, 0.2, 0.5, -1);
	show_hudmessage(0, "%L", LANG_PLAYER, "GP_TOWER_DOWN");
	// end the round without ReAPI: the defending team dies
	for (new p = 1; p <= MaxClients; p++)
		if (is_user_alive(p) && _:cs_get_user_team(p) == g_tower_team)
			user_silentkill(p);
	return HAM_IGNORED;
}

public tower_gone(ent)
{
	if (pev_valid(ent))
		remove_entity(ent);
}

// ---------------------------------------------------------------- language: %L reads the player's "lang" setinfo
public cmd_lang(id)
{
	new code[8];
	read_argv(1, code, charsmax(code));
	if (code[0])
	{
		set_user_info(id, "lang", code);
		client_print(id, print_center, "%L", id, "GP_LANG_NOW");
	}
	return PLUGIN_HANDLED;
}
