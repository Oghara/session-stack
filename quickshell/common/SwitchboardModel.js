.pragma library

// Qt's JavaScript engine does not implement Object.fromEntries.
function fromPairs(entries) {
    const result = {};
    entries.forEach(pair => { result[pair[0]] = pair[1]; });
    return result;
}

// math
var clamp = (x) => Math.max(0, Math.min(1, x));

const ease = (x) => {
  x = clamp(x);
  return x * x * (3 - 2 * x);
};

var span = (t, a, b) => ease((t - a) / (b - a));

function ortho(a, b) {
  const mid = (a.y + b.y) / 2;
  return [
    [a.x, a.y],
    [a.x, mid],
    [b.x, mid],
    [b.x, b.y],
  ];
}

function path(points) {
  return points.map((p, i) => (i ? "L" : "M") + p.join(" ")).join(" ");
}

// timeline
// Seconds on the preview clock; outcome branches share the opening battle.
const timeline = {
  awaitCredential: 2.8,
  authResult: 5.2,
  sessionReady: 8.8,
  boot: {
    auditAdvance: 1.82,
    policyAdvance: 1.99,
    brokerAdvance: 2.15,
    displayHeld: 2.07,
    policyHeld: 2.24,
    brokerHeld: 2.42,
  },
  ice: { awake: 3.2, brokerAttack: 3.35, brokerLost: 4.05, policyAttack: 4.15, containment: 4.9 },
  success: {
    brokerAssault: 5.5,
    brokerRecaptured: 6.15,
    relayAssault: 6.55,
    relayBreached: 7.35,
    portAdvance: 7.55,
  },
  failure: {
    policyCollapse: 5.4,
    policyLost: 5.8,
    displayAttack: 6.15,
    displayLost: 6.55,
    coreHeld: 7.2,
  },
  recovery: {
    backdoorOpen: 9.7,
    leechLoad: 10.1,
    brokerHeld: 10.8,
    ghostLoad: 10.8,
    wraithLoad: 11.2,
    residentsLive: 11.9,
    firewallRearmed: 12.6,
    maskBus: 12.7,
    ready: 13.2,
  },
  breaker: {
    load: 7.3,
    unfold: 7.55,
    fold: 8.4,
    farewell: 12.05,
    returnStart: 12.38,
    collapseStart: 12.68,
    lineHold: 12.84,
    pinchStart: 13.01,
    dotStart: 13.1,
  },
};

const workerEvents = {
  wraith: { death: timeline.failure.displayLost, recoverySeed: timeline.recovery.wraithLoad },
  ghost: { death: timeline.failure.policyLost, recoverySeed: timeline.recovery.ghostLoad },
  leech: { death: timeline.ice.brokerLost, recoverySeed: timeline.recovery.leechLoad },
};

const routeRecovery = {
  core: timeline.recovery.wraithLoad,
  display: timeline.recovery.ghostLoad,
  policy: timeline.recovery.leechLoad,
  broker: timeline.recovery.residentsLive,
};

// topology
const nodes = [
  { id: "core", name: "SESSION CORE", x: 600, y: 30, kind: "core" },
  { id: "audit", name: "AUDIT SPINE", x: 320, y: 98 },
  { id: "display", name: "DISPLAY SEAL", x: 455, y: 98 },
  { id: "policy", name: "POLICY GATE", x: 735, y: 156 },
  { id: "watch", name: "TRACE WATCH", x: 870, y: 156 },
  { id: "sensor", name: "SENSOR MESH", x: 300, y: 214 },
  { id: "broker", name: "IDENTITY BROKER", x: 505, y: 214 },
  { id: "ice", name: "ICE RELAY", x: 680, y: 273, kind: "ice" },
  { id: "recovery", name: "RECOVERY LINK", x: 875, y: 273 },
  { id: "eject", name: "EJECTION BUS", x: 870, y: 344 },
  { id: "access", name: "CREDENTIAL PORT", x: 600, y: 344 },
];

const byId = fromPairs(nodes.map((n) => [n.id, n]));

const chain = ["core", "display", "policy", "broker", "ice", "access"];

const branches = [
  ["display", "audit"],
  ["policy", "watch"],
  ["broker", "sensor"],
  ["ice", "recovery"],
  ["recovery", "eject"],
];

const nodeLabelOffsets = {
  core: [29, -7, "start"],
  display: [18, -10, "start"],
  policy: [-18, -10, "end"],
  broker: [18, -10, "start"],
  ice: [-54, -10, "end"],
  recovery: [-18, -10, "end"],
  eject: [-18, -10, "end"],
  access: [-18, -10, "end"],
};

const workers = [
  {
    id: "wraith",
    title: "// WRAITH.01",
    x: 18,
    y: 23,
    w: 245,
    start: 0.9,
    entry: "audit",
    node: "display",
  },
  {
    id: "ghost",
    title: "./GHOST:02",
    x: 945,
    y: 114,
    w: 237,
    start: 1.02,
    entry: "watch",
    node: "policy",
  },
  {
    id: "leech",
    title: "[ LEECH / 03 ]",
    x: 18,
    y: 237,
    w: 245,
    start: 1.14,
    entry: "sensor",
    node: "broker",
  },
];

const assignment = fromPairs(
  nodes.map((n, i) => {
    const worker = workers.find((w) => w.entry === n.id);
    return [
      n.id,
      { start: worker ? worker.start + 0.4 : n.id === "core" ? 0.75 : 1.35 + i * 0.075 },
    ];
  }),
);

// workers
function workerModel(w, frame) {
  const {
    t,
    accepted,
    recovering,
    restored,
    fighting,
    turned,
    iceIntegrity,
    brokerLoss,
    policyPressure,
    nodeStates,
  } = frame;

  const n = nodeStates.find((n) => n.id === w.node),
    scan = span(t, w.start + 0.4, w.start + 0.72),
    probe = span(t, w.start + 0.72, w.start + 0.92),
    deathAt = workerEvents[w.id].death;
  const killed = w.id === "leech" ? t >= deathAt : !accepted && t >= deathAt;
  const seedAt = accepted ? timeline.success.brokerRecaptured : workerEvents[w.id].recoverySeed;
  const rebuilt = accepted ? w.id === "leech" && t >= seedAt : recovering && t >= seedAt;
  const rebuild = rebuilt ? span(t, seedAt, seedAt + (accepted ? 0.4 : 0.7)) : 0;
  const dead = killed && !rebuilt,
    destruction = killed ? span(t, deathAt, deathAt + 0.3) * (1 - rebuild) : 0;
  const initialLoad = span(t, w.start, w.start + 0.4),
    replacement = rebuilt,
    loading = rebuilt ? t < seedAt + 0.28 : t >= w.start && initialLoad < 1,
    running = !dead && (rebuilt ? !loading : initialLoad >= 1);
  let health = 1;
  if (w.id === "leech") health = 1 - brokerLoss;
  if (w.id === "ghost") health = 1 - policyPressure * 0.55;
  if (!accepted && w.id === "ghost")
    health *= 1 - span(t, timeline.failure.policyCollapse, timeline.failure.policyLost);
  if (!accepted && w.id === "wraith")
    health *= 1 - span(t, timeline.failure.displayAttack, timeline.failure.displayLost);
  if (accepted && w.id === "ghost")
    health = Math.max(health, span(t, timeline.authResult, timeline.success.brokerAssault));
  if (rebuilt) health = span(t, seedAt + 0.28, seedAt + (accepted ? 0.4 : 0.7));
  if (!running) health = 0;
  let op = scan < 1 ? "scan" : probe < 1 ? "probe" : "hold",
    line1 = `> scan(${w.entry})`,
    line2 = `ports.enumerate :: ${Math.round(scan * 100)}%`,
    line3 = "then -> inject resident hook",
    progress = scan;
  if (scan >= 1) {
    line1 = `> inject(${w.entry})`;
    line2 = `resident.hook :: ${Math.round(probe * 100)}%`;
    line3 =
      probe >= 1
        ? n.claim >= 0.999
          ? "station captured / route held"
          : "hook live / advance in progress"
        : "writing resident hook";
    progress = probe;
    if (probe >= 1) {
      line1 = `> pivot(${w.entry} -> ${w.node})`;
      line2 =
        n.claim >= 0.999
          ? "downstream station / HELD"
          : "downstream claim / " + Math.round(n.claim * 100) + "%";
      line3 = "local ingress / resident hook";
    }
  }
  const attacked =
    w.id === "leech"
      ? t >= timeline.ice.brokerAttack
      : w.id === "ghost"
        ? t >= timeline.ice.policyAttack
        : !accepted && t >= timeline.failure.displayAttack;
  if (attacked && fighting) {
    op = "resist";
    line1 = `! ${w.node}.station => CONTEST`;
    line2 = `hook.integrity :: ${Math.round(health * 100)}%`;
    line3 = `${w.entry} -> ${w.node} / fight`;
    progress = health;
  }
  if (dead) {
    op = "dead";
    line1 = `! ${w.id}.process => DESTROYED`;
    line2 = `${w.entry}.ingress => ICE`;
    line3 = w.id === "leech" ? "core dump / hook severed" : "no resident / channel dark";
    progress = 0;
  }
  if (rebuilt) {
    if (loading) {
      op = "load";
      line1 = `> exec(${w.id}) => NEW PID`;
      line2 = `image.copy :: ${Math.round(span(t, seedAt, seedAt + 0.28) * 100)}%`;
    } else if (recovering) {
      op = "hold";
      line1 = w.id === "leech" ? "> leech.spawn(peers)" : `> ${w.id}.hold(${w.node})`;
      line2 = `hook.integrity :: ${Math.round(health * 100)}%`;
    } else {
      op = "fight";
      line1 = "> leech.advance(ice_relay)";
      line2 = `ICE.integrity :: ${Math.round(iceIntegrity * 100)}%`;
    }
    if (rebuild < 1) {
      line3 = `fresh image / ${w.entry}`;
      progress = rebuild;
    } else if (recovering) {
      line3 = `${w.entry} -> ${w.node} / held`;
      progress = 1;
    } else {
      line3 = "sensor -> broker -> ICE";
      progress = 1 - iceIntegrity;
    }
  }

  if (loading && !rebuilt) {
    op = "load";
    line1 = `> load(${w.id}.img)`;
    line2 = `payload.copy :: ${Math.round(initialLoad * 100)}%`;
    line3 = "map image -> exec -> scan";
    progress = initialLoad;
  }
  if (accepted && w.id !== "leech" && turned) {
    op = "fight";
    line1 = w.id === "wraith" ? "> wraith.hold(display)" : "> ghost.route.push(broker)";
    line2 = w.id === "wraith" ? "audit -> display / hold" : "watch -> policy -> broker";
    line3 =
      t < timeline.success.brokerRecaptured
        ? "eject callback => INTERCEPTED"
        : "broker secured / relay assault";
    progress = 1;
  }
  if (accepted && t >= timeline.sessionReady) {
    op = "owned";
    line1 = "> session.handoff()";
    line2 = "route.owner :: LOCAL";
    line3 = "resident retired / session ready";
    progress = 1;
  }
  if (restored) {
    op = "hold";
    line1 = `> pivot(${w.entry} -> ${w.node})`;
    line2 = "resident.hook :: 100%";
    line3 = "local ingress / route held";
    progress = 1;
  }
  return Object.assign({}, w, {
    target: { x: byId[w.entry].x, y: byId[w.entry].y },
    health,
    dead,
    destruction,
    rebuild,
    replacement,
    loading,
    running,
    initialLoad,
    attacked,
    op,
    line1,
    line2,
    line3,
    progress,
    opacity: span(t, w.start, w.start + 0.28),
    reveal: rebuilt ? span(t, seedAt, seedAt + 0.28) : span(t, w.start, w.start + 0.35),
    connected: span(t, w.start + 0.3, w.start + 0.4),
  });
}

// model
function breakerDeparture(m) {
  const t = m.recovering ? m.t : 0,
    times = timeline.breaker;
  return {
    active: t >= times.farewell,
    disconnecting: t >= times.returnStart,
    returning: span(t, times.returnStart, times.collapseStart),
    unplug: span(t, times.collapseStart, times.lineHold),
    collapse: span(t, times.collapseStart, times.lineHold),
    erase: span(t, times.pinchStart, times.dotStart),
    afterglow: span(t, times.dotStart, timeline.recovery.ready),
    status:
      t >= times.collapseStart
        ? "UNLOADING"
        : t >= times.returnStart
          ? "DISCONNECTING"
          : "TRACE CLEAN",
  };
}

function sceneModel(t, outcome, recovery = false) {
  const accepted = outcome === "success",
    recovering = !accepted && recovery && t >= timeline.sessionReady,
    restored = recovering && t >= timeline.recovery.ready;
  const fighting = t >= timeline.ice.awake,
    turned = t >= timeline.authResult,
    done = (t >= timeline.sessionReady && !recovering) || restored;
  const counter = span(t, timeline.ice.awake, timeline.ice.containment),
    suppression = span(t, 3.5, timeline.ice.containment);
  const retaliation = accepted
    ? span(t, timeline.authResult, timeline.success.relayBreached)
    : recovering
      ? span(t, 9.6, 12.5)
      : 0;
  const iceIntegrity = accepted
    ? 1 - span(t, timeline.success.relayAssault, timeline.success.relayBreached)
    : recovering
      ? 1 -
        0.8 *
          span(t, timeline.recovery.backdoorOpen, timeline.recovery.wraithLoad) *
          (1 - span(t, timeline.recovery.residentsLive, 13))
      : 1;
  const trace =
    counter *
    (accepted
      ? 1 - span(t, 6.8, 8.3)
      : recovering
        ? 1 - span(t, 10.4, timeline.recovery.maskBus)
        : 1);
  const capture = {
    core: span(t, 0.85, 1.25),
    display: span(t, timeline.boot.auditAdvance, timeline.boot.displayHeld),
    policy: span(t, timeline.boot.policyAdvance, timeline.boot.policyHeld),
    broker: span(t, timeline.boot.brokerAdvance, timeline.boot.brokerHeld),
    ice: 0,
    access: 0,
  };
  const brokerLoss = span(t, timeline.ice.brokerAttack, timeline.ice.brokerLost),
    policyPressure = span(t, timeline.ice.policyAttack, timeline.ice.containment);
  capture.broker *= 1 - brokerLoss;
  capture.policy *= 1 - policyPressure * 0.4;
  if (accepted) {
    capture.policy = Math.max(
      capture.policy,
      span(t, timeline.authResult, timeline.success.brokerAssault),
    );
    capture.broker = Math.max(
      capture.broker,
      span(t, timeline.success.brokerAssault, timeline.success.brokerRecaptured),
    );
    capture.ice = span(t, timeline.success.relayAssault, timeline.success.relayBreached);
    capture.access = span(t, timeline.success.portAdvance, timeline.sessionReady);
  } else if (t >= timeline.authResult) {
    capture.policy *= 1 - span(t, timeline.failure.policyCollapse, timeline.failure.policyLost);
    capture.display *= 1 - span(t, timeline.failure.displayAttack, timeline.failure.displayLost);
    capture.core = 1;
  }
  if (recovering) {
    capture.broker = span(t, 10.38, timeline.recovery.brokerHeld);
    capture.policy = span(t, 11.08, 11.5);
    capture.display = span(t, 11.48, timeline.recovery.residentsLive);
    capture.ice = 0;
    capture.eject =
      span(t, timeline.sessionReady, timeline.recovery.backdoorOpen) *
      (1 - span(t, timeline.recovery.maskBus, timeline.recovery.ready));
  }
  const raw = [
    timeline.boot.auditAdvance,
    timeline.boot.policyAdvance,
    timeline.boot.brokerAdvance,
    timeline.boot.brokerHeld,
  ]
    .map((a) => span(t, a, a + 0.27))
    .concat(0);
  const enemy = [
    accepted ? 0 : span(t, timeline.failure.displayLost, timeline.failure.coreHeld) * 0.87,
    accepted ? 0 : span(t, timeline.failure.policyLost, timeline.failure.displayLost),
    span(t, timeline.ice.brokerLost, timeline.ice.containment) *
      (accepted ? 1 - span(t, timeline.authResult, timeline.success.brokerAssault) : 1),
    span(t, timeline.ice.awake, timeline.ice.brokerLost) *
      (accepted
        ? 1 - span(t, timeline.success.brokerAssault, timeline.success.brokerRecaptured)
        : recovering
          ? 1 - span(t, 9.3, 10)
          : 1),
    0,
  ];
  const edges = raw.map((p, i) => p * (1 - enemy[i]));
  if (accepted) {
    edges[3] = Math.max(edges[3], capture.ice);
    edges[4] = capture.access;
  }
  if (recovering) {
    [0, 1, 2, 3].forEach((i) => {
      const a = routeRecovery[chain[i]],
        r = span(t, a, a + 0.7);
      enemy[i] *= 1 - r;
      edges[i] = 1 - enemy[i];
    });
    edges[4] = 0;
  }
  const reclaimed = edges.map((p, i) =>
    accepted && t > timeline.authResult ? p : recovering && i < 4 ? p : 0,
  );
  const nodeStates = nodes.map((n) => {
    const task = assignment[n.id],
      resident = workers.some((w) => w.entry === n.id),
      scan = span(t, task.start, task.start + (resident ? 0.32 : 0.24)),
      probe = span(t, task.start + (resident ? 0.32 : 0.24), task.start + (resident ? 0.52 : 0.46));
    const claim = capture[n.id] || 0,
      claimable = n.id in capture;
    let owner = claim >= 0.999 ? "daemon" : claim > 0.001 ? "contested" : "host";
    let label = nodeLabel(scan, owner, claimable);
    if (n.id === "ice" && scan === 1 && claim === 0)
      label = fighting ? "ICE / ACTIVE" : "ICE / SEALED";
    if (n.id === "broker" && t >= timeline.ice.brokerLost && t < timeline.success.brokerAssault)
      label = "RETAKEN / ICE";
    if (n.id === "core" && t >= timeline.failure.displayLost && !accepted)
      label = "FIREWALL / HOLDS";
    if (n.id === "eject" && recovering) {
      label =
        t < timeline.recovery.backdoorOpen
          ? "HANDLER / CORRUPTING"
          : t < timeline.recovery.maskBus
            ? "BACKDOOR / OPEN"
            : "BACKDOOR / MASKING";
    }
    if (restored && n.id === "core") label = "CAPTURED";
    if (n.id === "access") {
      label =
        accepted && t >= timeline.sessionReady
          ? "SESSION OPEN"
          : restored
            ? "RETRY READY"
            : "AUTH / SEALED";
      if (restored) owner = "retry";
    }
    return Object.assign({}, n, { task, scan, probe, claimable, claim, owner, label });
  });
  const workerFrame = {
    t,
    accepted,
    recovering,
    restored,
    fighting,
    turned,
    iceIntegrity,
    brokerLoss,
    policyPressure,
    nodeStates,
  };
  const activeWorkers = workers.map((worker) => workerModel(worker, workerFrame));

  for (const w of activeWorkers) {
    const n = nodeStates.find((n) => n.id === w.entry);
    n.claim = span(t, w.start + 0.72, w.start + 0.92) * w.health;
    n.claimable = true;
    n.owner = n.claim >= 0.999 ? "daemon" : n.claim > 0.001 ? "contested" : "host";
    if (n.scan >= 1)
      n.label = w.dead
        ? "INGRESS / LOST"
        : n.owner === "daemon"
          ? "INGRESS / HELD"
          : n.owner === "contested"
            ? "INGRESS / CONTEST"
            : "INGRESS / PROBE";
  }
  const alive = activeWorkers.filter((w) => w.running).length,
    daemonHealth = activeWorkers.reduce((a, w) => a + w.health, 0) / 3,
    route = edges.reduce((a, b) => a + b, 0) / 5;
  const phase = phaseAt(t);
  const eventList = [
    [0.9, "> WRAITH image / loading"],
    [1.02, "> GHOST image / loading"],
    [1.14, "> LEECH image / loading"],
    [1.3, "+ WRAITH exec / scan AUDIT"],
    [1.42, "+ GHOST exec / scan WATCH"],
    [1.54, "+ LEECH exec / scan SENSOR"],
    [timeline.boot.auditAdvance, "+ AUDIT => advance DISPLAY"],
    [1.94, "+ WATCH => advance POLICY"],
    [2.06, "+ SENSOR => advance BROKER"],
    [timeline.boot.displayHeld, "+ DISPLAY station captured"],
    [timeline.boot.policyHeld, "+ POLICY station captured"],
    [2.5, "+ inventory.scan => 11 / 11"],
    [timeline.boot.brokerHeld, "+ BROKER station captured"],
    [2.7, "! advance stopped / ICE RELAY"],
    [timeline.ice.awake, "! ICE sortie => BROKER"],
    [timeline.ice.brokerLost, "! BROKER retaken / LEECH TERMINATED"],
    [timeline.ice.policyAttack, "! ICE advances => POLICY"],
    [timeline.ice.containment, "! GHOST holds / WRAITH reinforces"],
  ];
  if (accepted)
    eventList.push(
      [timeline.authResult, "+ eject callback intercepted"],
      [timeline.success.brokerAssault, "> GHOST counterattack => BROKER"],
      [timeline.success.brokerRecaptured, "+ BROKER retaken / launch fresh LEECH"],
      [timeline.success.relayAssault, "> new LEECH assaults RELAY"],
      [timeline.success.relayBreached, "+ ICE RELAY captured"],
      [timeline.success.portAdvance, "> final advance => AUTH PORT"],
      [timeline.sessionReady, "+ accepted session => OPEN"],
    );
  else
    eventList.push(
      [timeline.authResult, "! auth rejected / no callback"],
      [timeline.failure.policyLost, "! POLICY lost / GHOST TERMINATED"],
      [timeline.failure.displayLost, "! DISPLAY lost / WRAITH TERMINATED"],
      [7.2, "+ CORE firewall => HOLDING"],
      [7.7, "> emergency patch => LOADING"],
      [timeline.sessionReady, "> NETRUN.ICEBREAKER => ARMED"],
    );
  if (recovering)
    eventList.push(
      [timeline.sessionReady, "> eject.handler => CORRUPTING"],
      [timeline.recovery.backdoorOpen, "+ EJECTION BUS => BACKDOOR PORT"],
      [timeline.recovery.leechLoad, "> broker tunnel / seed SENSOR"],
      [timeline.recovery.brokerHeld, "+ BROKER held / new GHOST image"],
      [timeline.recovery.wraithLoad, "> LEECH => new WRAITH image"],
      [timeline.recovery.residentsLive, "+ three residents => LIVE"],
      [timeline.recovery.firewallRearmed, "> firewall baseline => REARMED"],
      [timeline.recovery.ready, "+ credential input => READY"],
    );
  const battle = battleStatus(t, { accepted, recovering, restored });
  const meterLabels = [
    trace > 0.8 ? "LOCK" : trace > 0.01 ? "TRACK" : "CLEAR",
    iceIntegrity < 0.01 ? "DOWN" : fighting ? "ACTIVE" : "SEALED",
    alive + " / 3",
    restored ? "RETRY" : accepted && done ? "OWNED" : route > 0.01 ? "HELD" : "LOST",
  ];
  return {
    t,
    accepted,
    recovering,
    restored,
    fighting,
    turned,
    done,
    phase,
    counter,
    suppression,
    retaliation,
    iceIntegrity,
    trace,
    daemonHealth,
    raw,
    enemy,
    reclaimed,
    edges,
    route,
    nodeStates,
    workers: activeWorkers,
    count: nodeStates.filter((n) => n.scan >= 1).length,
    alive,
    gateOpen: accepted ? span(t, timeline.success.relayBreached, timeline.success.portAdvance) : 0,
    portOpen: accepted && t >= timeline.sessionReady,
    meters: [trace, iceIntegrity, daemonHealth, route],
    meterLabels,
    eventList,
    battle,
  };
}

function phaseAt(t) {
  if (t < 0.12) return 0;
  if (t < 1.15) return 1;
  if (t < 2.7) return 2;
  if (t < timeline.ice.awake) return 3;
  if (t < 4.7) return 4;
  if (t < timeline.authResult) return 5;
  if (t < timeline.sessionReady) return 6;
  return 7;
}

function battleStatus(t, { accepted, recovering, restored }) {
  if (restored) return "THREE RESIDENTS READY / WAITING FOR CREDENTIAL";
  if (recovering) {
    if (t < timeline.recovery.backdoorOpen) return "CORRUPTING EJECTION BUS / OPENING BACKDOOR";
    if (t < timeline.recovery.brokerHeld) return "BACKDOOR TUNNEL / LOADING NEW LEECH";
    if (t < timeline.recovery.residentsLive) return "LEECH LAUNCHES NEW GHOST + WRAITH";
    return "RESTORING AUTH CHANNEL / MASKING BACKDOOR";
  }
  if (t < 0.9) return "MILITECH SWITCHBOARD / LOCAL AUDIT";
  if (t < 1.54) return "DECK INJECTION / LOAD → EXECUTE → SCAN";
  if (t < timeline.ice.awake) return "ADVANCE / CORE → DISPLAY → POLICY → BROKER";
  if (t < timeline.ice.brokerLost) return "ICE SORTIE / RELAY → BROKER";
  if (t < timeline.ice.policyAttack) return "BROKER LOST / LEECH DESTROYED";
  if (t < timeline.authResult) return "POLICY CONTESTED / GHOST HOLDS";
  if (accepted) {
    if (t < timeline.success.brokerRecaptured) return "COUNTERATTACK / POLICY → BROKER";
    if (t < timeline.success.relayBreached) return "BROKER RETAKEN / ASSAULT ICE RELAY";
    if (t < timeline.sessionReady) return "RELAY CAPTURED / ADVANCE TO AUTH";
    return "SESSION ROUTE CAPTURED";
  }
  if (t < timeline.failure.policyLost) return "POLICY OVERRUN / GHOST FALLING";
  if (t < timeline.failure.displayLost) return "DISPLAY UNDER SIEGE / WRAITH ALONE";
  if (t < timeline.sessionReady) return "CORE FIREWALL HOLDS / EJECTION BUS EXPOSED";
  return "CORE HELD / ICEBREAKER ARMED";
}

function nodeLabel(scan, owner, claimable) {
  if (scan < 1) return scan > 0 ? "SCANNING" : "UNSCANNED";
  if (owner === "daemon") return "CAPTURED";
  if (owner === "contested") return "CONTESTED";
  return claimable ? "HOST CONTROL" : "SCANNED / HOST";
}

// terminal-copy
function consoleScript(m) {
  const script = (key, title, prompt, host, runner) => ({ key, title, prompt, host, runner });
  if (m.restored || (m.t >= timeline.boot.brokerHeld && !m.fighting))
    return script(
      "hold",
      "MILITECH / LOCAL AUDIT",
      "audit --local",
      [
        "> auth challenge / awaiting response",
        "> ICE relay / seal remains armed",
        "> local audit / no credential supplied",
        "> session core / boundary intact",
      ],
      [
        "+ WRAITH masks the audit footprint",
        "+ GHOST loops the trace-watch return",
        "+ LEECH holds the sensor foothold",
        "> processes on station / hold for credential",
        "> deck signature / decoy cycling",
      ],
    );
  if (m.t >= 1.54 && m.t < timeline.boot.brokerHeld)
    return script(
      "ingress",
      "MILITECH / LOCAL AUDIT",
      "audit --branches",
      [
        "> audit spine / resident traffic",
        "> trace watch / return route sampled",
        "> broker challenge / waiting on vector",
        "> ICE relay / seal remains armed",
      ],
      [
        "> WRAITH / audit to display",
        "> GHOST / watch to policy",
        "> LEECH / sensor to broker",
        "> local footholds / push toward the relay",
      ],
    );
  if (m.t >= 0.9 && m.t < 1.54)
    return script(
      "load",
      "MILITECH / LOCAL AUDIT",
      "audit --processes",
      [
        "> mapped pages / unsigned image",
        "> local process / signature absent",
        "> scheduler / new execution request",
      ],
      [
        "> copy daemon images into host memory",
        "> map executable pages / bind local sockets",
        "> launch fresh PIDs / scan after exec",
      ],
    );
  if (m.t < timeline.ice.awake)
    return script(
      "jack",
      "MILITECH / LOCAL AUDIT",
      "audit --ingress",
      [
        "> local subnet / enumerate endpoints",
        "> audit spool / channel heartbeat",
        "> watch relay / sampling deck traffic",
        "> identity broker / challenge staged",
      ],
      [
        "> jack in / isolate neural feedback",
        "> deck route / local datafort only",
        "> mount unsigned residents / local ingress",
        "> handshake complete / enumerate ports",
      ],
    );
  if (m.recovering) {
    if (m.t < timeline.recovery.backdoorOpen)
      return script(
        "bus",
        "BLACK ICE / EJECT FAULT",
        "eject --retry",
        [
          "! ejection handler / write collision",
          "! return vector / foreign payload",
          "! bus integrity / checksum mismatch",
          "! purge request / handler not responding",
        ],
        [
          "> ICEBREAKER / jack the exposed bus",
          "> hook eject return / wedge payload",
          "+ core firewall / keep the deck anchored",
          "> rewrite bus / build a backdoor",
        ],
      );
    if (m.t < timeline.recovery.residentsLive)
      return script(
        "reseed",
        "BLACK ICE / COUNTER-ICE",
        "contain --payload",
        [
          "! foreign resident / crossed broker",
          "! sensor mesh / new process signature",
          "! containment sweep / hook survives",
          "! peer traffic / quarantine slipping",
        ],
        [
          "+ backdoor open / tunnel through broker",
          "> launch fresh LEECH at sensor mesh",
          "> LEECH sends GHOST + WRAITH images",
          "> restore footholds / leave auth sealed",
        ],
      );
    return script(
      "mask",
      "MILITECH / AUDIT RESYNC",
      "audit --resync",
      [
        "> relay watchdog / restore ICE baseline",
        "> audit spool / reconciling local state",
        "> challenge channel / restoring input",
        "> session boundary / still locked",
      ],
      [
        "+ three fresh processes / hooks established",
        "> mask the bus / bury the return hook",
        "> feed audit a nominal heartbeat",
        "+ new PIDs hold / credential required",
      ],
    );
  }
  if (m.accepted && m.turned) {
    if (m.t < timeline.success.brokerRecaptured)
      return script(
        "callback",
        "BLACK ICE / CALLBACK FAULT",
        "eject --retry",
        [
          "! eject handler / callback intercepted",
          "! policy gate / resident counterfire",
          "! broker ownership / contested",
          "! purge payload / retry denied",
        ],
        [
          "+ credential accepted / callback caught",
          "> GHOST pushes from watch through policy",
          "> reclaim broker / open a seed route",
          "+ WRAITH keeps audit ingress alive",
        ],
      );
    if (m.t < timeline.success.relayBreached)
      return script(
        "assault",
        "PAYLOAD / RELAY ASSAULT",
        "payload --relay",
        [
          "! ICE integrity / fragments dropping",
          "! relay failover / resident in the path",
          "! purge vector / callback still owned",
          "! broker quarantine / cannot rearm",
        ],
        [
          "+ broker retaken / LEECH image seeded",
          "> sensor -> broker / drive the payload",
          "> LEECH hammers the ICE relay",
          "> keep the trace chasing a decoy",
        ],
      );
    if (!m.portOpen)
      return script(
        "purge",
        "COUNTERTRACE / PURGE QUEUE",
        "trace --scrub",
        [
          "> ICE relay / defenses collapsed",
          "> auth route / accepted vector advancing",
          "> session bridge / handoff pending",
          "> audit queue / clearing stale trace",
        ],
        [
          "+ relay down / carry the accepted vector",
          "> scrub the deck return from the trace",
          "> hand the route to access control",
          "> hold the bridge / wait for handoff",
        ],
      );
    return script(
      "owned",
      "LOCAL ACCESS / HANDOFF",
      "session --handoff",
      [
        "+ accepted session / bridge open",
        "+ countertrace / no active lock",
        "> local control / handoff complete",
      ],
      [
        "+ node owned / accepted route committed",
        "+ deck trace / scrubbed",
        "> retire the residents / clean exit",
      ],
    );
  }
  if (m.t >= timeline.breaker.load)
    return script(
      m.t < timeline.sessionReady ? "loader" : "armed",
      "BLACK ICE / CORE SIEGE",
      "hunt --core",
      [
        "! core firewall / entry denied",
        "! ejection bus / deck still anchored",
        "! resident sweep / outer footholds dark",
        "! countertrace locked / retry core ingress",
        "! authentication channels / quarantine",
      ],
      m.t < timeline.sessionReady
        ? [
            "! processes terminated / core still holds",
            "> ICEBREAKER / mount unsigned payload",
            "> skull mesh / load the resident image",
            "> ejection bus exposed / prepare the hook",
          ]
        : [
            "! WRAITH / GHOST / LEECH / no heartbeat",
            "+ core firewall / last foothold holds",
            "> ICEBREAKER armed / waiting for injection",
            "> deck return / feed the trace a decoy",
            "! auth stays sealed / patch the bus",
          ],
    );
  if (m.t >= timeline.failure.policyLost)
    return script(
      "display",
      "BLACK ICE / DISPLAY ASSAULT",
      "hunt --display",
      [
        "! policy gate / containment complete",
        "! display seal / isolate WRAITH",
        "! audit spine / burn the resident hook",
        "! session core / next boundary",
      ],
      [
        "! GHOST lost / watch ingress severed",
        "! WRAITH alone / hold the upper route",
        "> core firewall / brace for the sweep",
        "> emergency bus / probe for a return",
      ],
    );
  if (m.t >= timeline.authResult)
    return script(
      "reject",
      "BLACK ICE / QUARANTINE",
      "seal --channels",
      [
        "! credential rejected / no callback",
        "! policy gate / drive out GHOST",
        "! auth channels / quarantine asserted",
        "! ejection order / route termination",
      ],
      [
        "! no accepted vector / callback absent",
        "! GHOST at policy / falling back",
        "> WRAITH / keep the audit hook alive",
        "> core firewall / preserve the foothold",
      ],
    );
  if (m.t >= timeline.ice.brokerLost)
    return script(
      "policy",
      "BLACK ICE / POLICY ASSAULT",
      "hunt --policy",
      [
        "! broker retaken / sensor hook burned",
        "! policy gate / acquire GHOST",
        "! deck return / countertrace converging",
        "! eject handler / arm the cut",
      ],
      [
        "! LEECH destroyed / sensor ingress lost",
        "> GHOST holds watch / contest policy",
        "> WRAITH reinforces through display",
        "! neural feedback / isolate hostile traffic",
        "> decoy return / pull the trace off deck",
      ],
    );
  return script(
    "broker",
    "BLACK ICE / BROKER ASSAULT",
    "hunt --broker",
    [
      "! unsigned deck / acquire return route",
      "! wake black ICE / protect the broker",
      "! sensor ingress / resident detected",
      "! purge LEECH / saturate the branch",
    ],
    [
      "! ICE awake / broker under pressure",
      "> LEECH / hold the sensor foothold",
      "> divert the trace / loop a decoy return",
      "! feedback spike / isolate the deck",
    ],
  );
}

function programOverview(view, m) {
  const programs = m.workers.map((w, i) => ({
    id: w.id,
    name: w.id.toUpperCase(),
    role: ["AUDIT COVER", "TRACE DECOY", "ROUTE GUARD"][i],
    status: workerProgramStatus(w, m.portOpen),
    detail: "PID " + processId(view, w, i) + (w.replacement ? " / FRESH IMAGE" : ""),
  }));
  const core = m.nodeStates.find((n) => n.id === "core");
  let coreStatus = "STANDBY";
  if (m.portOpen) coreStatus = "RETIRED";
  else if (core.claim >= 0.999) {
    const underSiege = m.fighting && !m.restored && m.t >= timeline.failure.displayLost && !m.accepted;
    coreStatus = underSiege ? "HOLDING" : "ACTIVE";
  } else if (core.claim > 0) coreStatus = "INITIALIZING";
  programs.push({
    id: "firewall",
    name: "CORE FIREWALL",
    role: "DECK ANCHOR",
    status: coreStatus,
    detail: "SESSION CORE / " + core.label,
  });
  const departure = breakerDeparture(m);
  let breakerStatus = "STANDBY";
  if (m.restored) breakerStatus = "COMPLETE";
  else if (departure.active) breakerStatus = departure.status;
  else if (m.recovering) {
    breakerStatus = m.t >= timeline.recovery.residentsLive ? "MASKING" : "ACTIVE";
  } else if (!m.accepted) {
    if (m.t >= timeline.sessionReady) breakerStatus = "ARMED";
    else if (m.t >= timeline.breaker.load) breakerStatus = "INITIALIZING";
  }

  let breakerDetail = "DEPLOY IF THE OUTER PROCESSES FALL";
  if (departure.active) {
    if (m.restored) breakerDetail = "PAYLOAD UNLOADED / RESIDENTS HOLD";
    else if (departure.unplug < 1) breakerDetail = "TRACE SCRUBBED / RESIDENTS HOLD";
    else breakerDetail = "LOCAL HOOK RELEASED / UNLOADING";
  } else if (!m.accepted && m.t >= timeline.breaker.load) {
    breakerDetail = m.recovering ? "BACKDOOR / FRESH IMAGES" : "EJECTION BUS / FIXED LINK";
  }
  programs.push({
    id: "breaker",
    name: "ICEBREAKER",
    role: "EMERGENCY INJECTION",
    status: breakerStatus,
    detail: breakerDetail,
  });
  let status = "PREPARING",
    action = "Deck link establishing.",
    detail = "Protective programs await injection.",
    focus = "firewall";
  if (m.restored) {
    status = "HOLDING";
    action = "Fresh processes hold the recovered route.";
    detail = "Authentication still required.";
    focus = "firewall";
  } else if (m.recovering) {
    status = "RECOVERY";
    if (departure.active) {
      action = departure.disconnecting
        ? "ICEbreaker releases its link and unloads."
        : "ICEbreaker scrubs its trace. Residents take over.";
    } else if (m.t < timeline.recovery.backdoorOpen) {
      action = "ICEbreaker corrupts the ejection bus.";
    } else if (m.t < 10.38) {
      action = "New Leech image loading through the backdoor.";
    } else if (m.t < timeline.recovery.brokerHeld) {
      action = "Leech establishes a new broker foothold.";
    } else if (m.t < timeline.recovery.residentsLive) {
      action = "Leech launches fresh Ghost and Wraith images.";
    } else {
      action = "Fresh processes hold. Backdoor is masking.";
    }
    detail = "Core firewall holds. Authentication stays locked.";
    focus = "breaker";
  } else if (m.portOpen) {
    status = "COMPLETE";
    action = "Accepted session open. Programs retire.";
    detail = "ICE defeated. Countertrace cleared.";
    focus = "";
  } else if (m.accepted && m.turned) {
    status = "COUNTERATTACK";
    if (m.t < timeline.success.brokerRecaptured) {
      action = "Ghost retakes broker through the callback.";
    } else if (m.t < 6.43) {
      action = "Fresh Leech image initializing.";
    } else if (m.t < timeline.success.relayBreached) {
      action = "New Leech process breaks the ICE relay.";
    } else {
      action = "ICE defeated. Clearing the deck trace.";
    }
    detail = "Wraith holds display. The accepted route advances.";
    focus = m.t < timeline.success.brokerRecaptured ? "ghost" : "leech";
  } else if (m.fighting) {
    status = m.t >= timeline.failure.displayLost ? "LAST DEFENSE" : "UNDER ATTACK";
    if (m.t < timeline.ice.brokerLost) {
      action = "Leech defends broker against the ICE advance.";
      focus = "leech";
    } else if (m.t < timeline.failure.policyLost) {
      action = "Leech defeated. Ghost holds policy.";
      focus = "ghost";
    } else if (m.t < timeline.failure.displayLost) {
      action = "Ghost defeated. Wraith defends display.";
      focus = "wraith";
    } else if (m.t < timeline.breaker.load) {
      action = "Outer processes defeated. Core firewall holds.";
      focus = "firewall";
    } else {
      action = m.t < timeline.sessionReady
        ? "ICEbreaker initializes for emergency injection."
        : "ICEbreaker armed. Waiting for injection.";
      focus = "breaker";
    }
    detail = m.t < timeline.authResult
      ? "Resident hooks resist countertrace and ejection."
      : "Credential rejected. Core remains anchored.";
  } else if (m.t >= timeline.awaitCredential) {
    status = "HOLDING";
    action = "All three daemons cover the local route.";
    detail = "Waiting for a credential at the sealed ICE relay.";
    focus = "";
  } else if (m.t >= 0.9) {
    status = "INJECTING";
    action =
      m.t < 1.54
        ? "Daemon images initialize inside the host."
        : "Active processes scan, claim and hold their nodes.";
    detail = "Each program executes only after its image loads.";
    focus = "";
  }
  return { programs, status, action, detail, focus };
}

function processId(view, w, i) {
  const { state } = view;
  return ((state.generation + (w.replacement ? 1 : 0)) * 256 + i + 1)
    .toString(16)
    .toUpperCase()
    .padStart(3, "0");
}


function frame(time, outcome, recovery, generation) {
    const m = sceneModel(time, outcome, recovery);
    m.departure = breakerDeparture(m);
    m.overview = programOverview({state: {generation: generation}}, m);
    m.console = consoleScript(m);
    m.workers.forEach((w, i) => { w.pid = processId({state: {generation: generation}}, w, i); });
    return m;
}
function links() { return {chain: chain, branches: branches, nodes: byId, labels: nodeLabelOffsets}; }

function workerProgramStatus(worker, portOpen) {
  if (worker.dead) return "DEFEATED";
  if (worker.loading) return "INITIALIZING";
  if (portOpen) return "RETIRED";
  if (!worker.running) return "STANDBY";
  return worker.op === "resist" ? "UNDER ATTACK" : "ACTIVE";
}

function route(points, progress) {
    let length = 0;
    for (let i = 1; i < points.length; i++)
        length += Math.hypot(points[i][0] - points[i-1][0], points[i][1] - points[i-1][1]);
    let remaining = length * clamp(progress);
    let d = 'M' + points[0].join(' ');
    for (let i = 1; i < points.length && remaining > 0; i++) {
        const a = points[i-1], b = points[i];
        const segment = Math.hypot(b[0]-a[0], b[1]-a[1]);
        const part = segment ? Math.min(1, remaining / segment) : 1;
        d += 'L' + (a[0]+(b[0]-a[0])*part) + ' ' + (a[1]+(b[1]-a[1])*part);
        remaining -= segment;
    }
    return d;
}

function overlay(m) {
    let title = 'LOCAL ACCESS // LOCKED', vector = '', command = '', note = '', progress = 0;
    if (m.restored) return {title: title, vector: '', command: '', note: '', progress: 0};
    if (m.t < 2.8) {
        const steps = ['DECK HANDSHAKE','GHOST ROUTE','RESIDENT HOOKS','IDENTITY SPOOF','CREDENTIAL CHANNEL'];
        title = steps[Math.min(4, Math.floor(m.t / 2.8 * 5))];
        command = '> load residents / bind credential channel';
        progress = m.t / 2.8;
    } else if (m.recovering) {
        title = 'ICEBREAKER // ATTACKING ICE SEAL';
        vector = 'NETRUN.ICEBREAKER // RECOVERY VECTOR';
        command = '> password.channel => ' + (m.t < 9.7 ? 'EJECTION BUS CORRUPTING' : m.t < 10.8 ? 'BACKDOOR TUNNEL' : m.t < 11.9 ? 'LAUNCHING NEW PROCESSES' : 'ACCESS RESTORING');
        progress = span(m.t, 8.8, 13.2);
        note = 'EMERGENCY PATCH / ' + Math.round(progress * 100) + '% / RESTORE INPUT';
    } else if (m.fighting) {
        if (m.t < 4.05) {
            title = 'BLACK ICE ENGAGED';
            vector = 'HOSTILE VECTOR // NODE 03';
            command = '> black_ice.acquire(deck) => TRACKING';
            progress = span(m.t, 3.2, 4.05) * 0.3;
        } else if (m.t < 5.2) {
            title = 'COUNTERTRACE LOCKED // EJECTION ARMED';
            vector = 'SECURITY CONTROL // DEFENSIVE RESPONSE';
            command = '> countermeasure.eject(deck) => EXECUTING';
            progress = 0.3 + span(m.t, 4.05, 5.2) * 0.2;
        } else if (m.accepted) {
            title = m.t < 6.15 ? 'PAYLOAD CALLBACK // EJECT HANDLER CAUGHT' : m.t < 7.35 ? 'INJECTION CONFIRMED // ICE UNSTABLE' : m.t < 8.8 ? 'BLACK ICE COLLAPSED' : 'NODE OWNED';
            vector = 'AUTHENTICATED VECTOR // NODE 03';
            command = m.t < 6.15 ? '> eject.handler.catch(payload) => INTERCEPTED' : m.t < 6.55 ? '> resident.reseed(leech) => COMMITTED' : m.t < 7.35 ? '> black_ice.shatter(relay) => IN PROGRESS' : '> trace.scrub(route) => CLEAN';
            progress = 0.5 + span(m.t, 5.2, 8.8) * 0.5;
        } else {
            title = m.t < 6.55 ? 'CONNECTION TERMINATED' : 'BLACK ICE // AUTH CHANNELS SEALED';
            vector = 'SECURITY CONTROL // QUARANTINE';
            command = '> password.channel => BLACK ICE SEALED';
            note = 'NETRUN.ICEBREAKER ARMED / DEPLOY PATCH TO RETRY';
            progress = 1;
        }
        if (!note) note = m.battle;
    }
    return {title: title, vector: vector, command: command, note: note, progress: progress};
}

function pointOnRoute(points, progress) {
    let total = 0;
    for (let i = 1; i < points.length; i++)
        total += Math.hypot(points[i][0]-points[i-1][0], points[i][1]-points[i-1][1]);
    let remaining = total * clamp(progress);
    for (let i = 1; i < points.length; i++) {
        const a = points[i-1], b = points[i];
        const length = Math.hypot(b[0]-a[0], b[1]-a[1]);
        if (remaining <= length && length > 0) {
            const fraction = remaining / length;
            return {x: a[0]+(b[0]-a[0])*fraction, y: a[1]+(b[1]-a[1])*fraction};
        }
        remaining -= length;
    }
    const last = points[points.length-1];
    return {x: last[0], y: last[1]};
}
