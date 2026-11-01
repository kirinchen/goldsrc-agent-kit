/* pj010_nadespray: hold a key to spray HE grenades (Counter-Strike 1.6, AMX Mod X 1.10)
 *   bind mouse3 +nadespray   -> while held, one HE grenade every ns_interval seconds flies out in front of you;
 *                               after ns_duration seconds it stops even if the key is still down (press again for more)
 *   ns_interval 0.05         -> seconds between grenades (cvar)
 *   ns_duration 5.0          -> longest spray per key press (cvar); 5.0 / 0.05 = 100 grenades
 * Each grenade is a real "grenade" entity (so the kill feed shows the HE icon) that bounces like an HE
 * and explodes 1.5 s later: HE sprite + sound, 100 damage falling off to 0 at 350 units, credited to you.
 * The thrower is never hurt by their own spray.
 */
#include <amxmodx>
#include <fakemeta>
#include <engine>
#include <hamsandwich>

#define NS_TAG 7101		// pev_iuser4 marker: only our grenades, never the game's own HE / flash / C4
#define NS_FUSE 1.5
#define NS_SPEED 600.0
#define NS_DAMAGE 100.0
#define NS_RADIUS 350.0

new g_cv_interval, g_cv_duration;
new bool:g_held[33], Float:g_next[33], Float:g_stop[33];
new g_exp;

public plugin_precache()
{
	g_exp = precache_model("sprites/zerogxplode.spr");
	precache_model("models/w_hegrenade.mdl");
	precache_sound("weapons/hegrenade-1.wav");
	precache_sound("weapons/hegrenade-2.wav");
}

public plugin_init()
{
	register_plugin("PJ-010 nade spray", "1.0", "goldsrc-agent-kit");
	register_clcmd("+nadespray", "cmd_spray_on");
	register_clcmd("-nadespray", "cmd_spray_off");
	g_cv_interval = register_cvar("ns_interval", "0.05");
	g_cv_duration = register_cvar("ns_duration", "5.0");
	register_think("grenade", "think_grenade");
	register_forward(FM_PlayerPreThink, "fw_PlayerPreThink");
}

public cmd_spray_on(id)
{
	if (!is_user_alive(id) || g_held[id])
		return PLUGIN_HANDLED;
	g_held[id] = true;
	g_next[id] = get_gametime();
	g_stop[id] = g_next[id] + get_pcvar_float(g_cv_duration);
	return PLUGIN_HANDLED;
}

public cmd_spray_off(id)
{
	g_held[id] = false;
	return PLUGIN_HANDLED;
}

public client_disconnected(id)
{
	g_held[id] = false;
}

// timing is checked every frame: set_task cannot repeat faster than 0.1 s.
// If a frame comes late, the grenades it missed are thrown together, so the count stays duration / interval
public fw_PlayerPreThink(id)
{
	if (!g_held[id])
		return;
	new Float:now = get_gametime(), Float:step = floatmax(get_pcvar_float(g_cv_interval), 0.01);
	if (!is_user_alive(id) || now >= g_stop[id])
	{
		g_held[id] = false;
		return;
	}
	while (g_next[id] <= now && g_next[id] < g_stop[id])
	{
		throw_one(id);
		g_next[id] += step;
	}
}

throw_one(id)
{
	// start 64 units ahead and a little below the eyes (closer, a grenade fills the whole screen),
	// pulled back if a wall is closer than that
	new Float:eye[3], Float:ofs[3], Float:fwd[3], Float:start[3], Float:end[3], Float:ang[3];
	pev(id, pev_origin, eye);
	pev(id, pev_view_ofs, ofs);
	eye[2] += ofs[2];
	pev(id, pev_v_angle, ang);
	engfunc(EngFunc_MakeVectors, ang);
	global_get(glb_v_forward, fwd);
	for (new i = 0; i < 3; i++)
		end[i] = eye[i] + fwd[i] * 64.0 - (i == 2 ? 10.0 : 0.0);
	engfunc(EngFunc_TraceLine, eye, end, IGNORE_MONSTERS, id, 0);
	get_tr2(0, TR_vecEndPos, start);
	for (new i = 0; i < 3; i++)
		start[i] -= fwd[i] * 8.0;

	// "grenade" is the game's own grenade class (no think or touch of its own until the game sets one),
	// and its classname makes the kill feed draw the HE icon. Its Spawn is not called: we set it up here
	new ent = create_entity("grenade");
	if (!pev_valid(ent))
		return;
	set_pev(ent, pev_movetype, MOVETYPE_BOUNCE);
	set_pev(ent, pev_solid, SOLID_BBOX);
	engfunc(EngFunc_SetModel, ent, "models/w_hegrenade.mdl");
	engfunc(EngFunc_SetSize, ent, Float:{ 0.0, 0.0, 0.0 }, Float:{ 0.0, 0.0, 0.0 });
	engfunc(EngFunc_SetOrigin, ent, start);
	set_pev(ent, pev_owner, id);	// does not collide with the thrower
	set_pev(ent, pev_iuser4, NS_TAG);
	set_pev(ent, pev_gravity, 0.55);
	set_pev(ent, pev_friction, 0.7);

	// a little random spread so the stream fans out
	new Float:vel[3], Float:pvel[3], Float:av[3];
	pev(id, pev_velocity, pvel);
	for (new i = 0; i < 3; i++)
		vel[i] = fwd[i] * NS_SPEED + random_float(-40.0, 40.0) + pvel[i];
	vel[2] += 60.0;
	set_pev(ent, pev_velocity, vel);
	av[0] = random_float(-400.0, 400.0);
	av[1] = random_float(-400.0, 400.0);
	set_pev(ent, pev_avelocity, av);
	set_pev(ent, pev_nextthink, get_gametime() + NS_FUSE);
}

public think_grenade(ent)
{
	if (pev(ent, pev_iuser4) != NS_TAG)
		return PLUGIN_CONTINUE;	// the game's own grenade: leave it alone
	explode(ent);
	return PLUGIN_HANDLED;
}

explode(ent)
{
	new Float:org[3], owner = pev(ent, pev_owner);
	pev(ent, pev_origin, org);

	// MSG_PVS needs the origin: without it the message goes to whoever can see the map origin (often nobody)
	engfunc(EngFunc_MessageBegin, MSG_PVS, SVC_TEMPENTITY, org, 0);
	write_byte(TE_EXPLOSION);
	engfunc(EngFunc_WriteCoord, org[0]);
	engfunc(EngFunc_WriteCoord, org[1]);
	engfunc(EngFunc_WriteCoord, org[2] + 20.0);
	write_short(g_exp);
	write_byte(30);	// scale
	write_byte(15);	// framerate
	write_byte(TE_EXPLFLAG_NOSOUND);
	message_end();
	emit_sound(ent, CHAN_WEAPON, random_num(0, 1) ? "weapons/hegrenade-1.wav" : "weapons/hegrenade-2.wav", 1.0, ATTN_NORM, 0, PITCH_NORM);

	// damage everything that can take it (players, hostages, breakables), not the thrower
	new victim = -1;
	while ((victim = engfunc(EngFunc_FindEntityInSphere, victim, org, NS_RADIUS)) > 0)
	{
		if (victim == ent || victim == owner || entity_get_float(victim, EV_FL_takedamage) == 0.0
			|| entity_get_float(victim, EV_FL_health) <= 0.0)
			continue;
		new Float:at[3];
		pev(victim, pev_origin, at);
		new Float:dmg = NS_DAMAGE * (1.0 - get_distance_f(org, at) / NS_RADIUS);
		if (dmg > 0.0)
			ExecuteHamB(Ham_TakeDamage, victim, ent, is_user_connected(owner) ? owner : ent, dmg, DMG_GRENADE);
	}
	engfunc(EngFunc_RemoveEntity, ent);
}
