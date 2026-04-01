(function () {
  var canvas = document.getElementById("gameCanvas");
  var ctx = canvas.getContext("2d");
  var titleScreen = document.getElementById("titleScreen");
  var startButton = document.getElementById("startButton");
  var hud = document.getElementById("hud");
  var messageOverlay = document.getElementById("messageOverlay");
  var hullBar = document.getElementById("hullBar");
  var fuelBar = document.getElementById("fuelBar");
  var heatBar = document.getElementById("heatBar");
  var hullText = document.getElementById("hullText");
  var fuelText = document.getElementById("fuelText");
  var heatText = document.getElementById("heatText");
  var scrapText = document.getElementById("scrapText");
  var distanceText = document.getElementById("distanceText");
  var statusText = document.getElementById("statusText");
  var objectiveText = document.getElementById("objectiveText");
  var titleScreenMarkup = titleScreen.innerHTML;
  var pointerLockSupported = !!(
    canvas.requestPointerLock ||
    canvas.mozRequestPointerLock ||
    canvas.webkitRequestPointerLock ||
    canvas.msRequestPointerLock
  );

  var keys = {};
  var state = "title";
  var lastTime = 0;
  var messageTimer = 0;
  var flashTimer = 0;
  var fireFlash = 0;
  var lastMessage = "";
  var pointerLocked = false;
  var mouseLookActive = false;
  var lastMouseX = null;
  var fullscreenActive = false;
  var mapWidth = 16;
  var mapHeight = 16;
  var tileSize = 1;
  var fov = Math.PI / 3;
  var maxDepth = 14;
  var rayStep = 0.02;
  var balance = {
    moveSpeed: 2.65,
    strafeSpeed: 2.1,
    sprintSpeed: 4.1,
    turnSpeed: 2.35,
    mouseSensitivity: 0.0021,
    idleFuelDrain: 0.7,
    moveFuelDrain: 1.55,
    sprintFuelDrain: 3.2,
    weaponHeatPerShot: 26,
    weaponHeatCooldown: 18,
    enemyDamage: 11,
    enemyRange: 7.5,
    enemyFireDelay: 1.15,
    enemyMoveSpeed: 1.05,
    enemyChaseSpeed: 1.45,
    enemyRetreatSpeed: 1.25,
    enemyStrafeSpeed: 1.1,
    enemyFlankSpeed: 1.55,
    enemyFlankOffset: 1.55,
    enemyDodgeSpeed: 2.45,
    enemyDodgeDuration: 0.22,
    enemyDodgeCooldown: 1.35,
    enemyPatrolPause: 0.4,
    enemyPersonalSpace: 0.42,
    enemyStrafeMinTime: 0.7,
    enemyStrafeMaxTime: 1.4,
    pickupFuel: 16,
    pickupHull: 12,
    targetCores: 3
  };
  var worldMap = [
    "################",
    "#......#.......#",
    "#.##...#..##...#",
    "#.#....#.......#",
    "#.#.#####.###..#",
    "#.#........#...#",
    "#.####..##.#.#.#",
    "#......#...#.#.#",
    "#.##.#.#.###.#.#",
    "#....#.#.....#.#",
    "###..#.#####.#.#",
    "#....#.....#.#.#",
    "#.####.###.#.#.#",
    "#......#...#...#",
    "#..E...#.......#",
    "################"
  ];

  var player;
  var pickups;
  var enemies;

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function distance(ax, ay, bx, by) {
    var dx = ax - bx;
    var dy = ay - by;
    return Math.sqrt(dx * dx + dy * dy);
  }

  function normalizeAngle(angle) {
    while (angle < -Math.PI) angle += Math.PI * 2;
    while (angle > Math.PI) angle -= Math.PI * 2;
    return angle;
  }

  function isWall(x, y) {
    var mapX = Math.floor(x);
    var mapY = Math.floor(y);
    if (mapX < 0 || mapY < 0 || mapX >= mapWidth || mapY >= mapHeight) {
      return true;
    }
    return worldMap[mapY].charAt(mapX) === "#";
  }

  function canMoveTo(x, y) {
    var radius = 0.18;
    return !isWall(x - radius, y - radius) &&
      !isWall(x + radius, y - radius) &&
      !isWall(x - radius, y + radius) &&
      !isWall(x + radius, y + radius);
  }

  function setMessage(text) {
    if (text === lastMessage && messageTimer > 0.3) {
      return;
    }
    lastMessage = text;
    messageOverlay.className = "message-overlay";
    messageOverlay.innerHTML = text;
    messageTimer = 2.2;
  }

  function getPointerLockElement() {
    return document.pointerLockElement ||
      document.mozPointerLockElement ||
      document.webkitPointerLockElement ||
      document.msPointerLockElement ||
      null;
  }

  function requestPointerLock() {
    var request = canvas.requestPointerLock ||
      canvas.mozRequestPointerLock ||
      canvas.webkitRequestPointerLock ||
      canvas.msRequestPointerLock;
    if (request) {
      request.call(canvas);
    }
  }

  function exitPointerLock() {
    var exit = document.exitPointerLock ||
      document.mozExitPointerLock ||
      document.webkitExitPointerLock ||
      document.msExitPointerLock;
    if (exit) {
      exit.call(document);
    }
  }

  function getFullscreenElement() {
    return document.fullscreenElement ||
      document.webkitFullscreenElement ||
      document.mozFullScreenElement ||
      document.msFullscreenElement ||
      null;
  }

  function toggleFullscreen() {
    var fullscreenElement = getFullscreenElement();
    var request;
    var exit;

    if (!fullscreenElement) {
      request = canvas.requestFullscreen ||
        canvas.webkitRequestFullscreen ||
        canvas.mozRequestFullScreen ||
        canvas.msRequestFullscreen;
      if (request) {
        request.call(canvas);
      }
    } else {
      exit = document.exitFullscreen ||
        document.webkitExitFullscreen ||
        document.mozCancelFullScreen ||
        document.msExitFullscreen;
      if (exit) {
        exit.call(document);
      }
    }
  }

  function refreshFullscreenState() {
    fullscreenActive = getFullscreenElement() === canvas;
  }

  function refreshMouseLookState() {
    pointerLocked = getPointerLockElement() === canvas;
    if (pointerLocked) {
      mouseLookActive = false;
      lastMouseX = null;
      canvas.style.cursor = "none";
    } else if (mouseLookActive) {
      canvas.style.cursor = "grabbing";
    } else {
      canvas.style.cursor = "crosshair";
    }
  }

  function applyMouseLook(deltaX) {
    if (state !== "playing" || !deltaX) {
      return;
    }
    player.angle = normalizeAngle(player.angle + deltaX * balance.mouseSensitivity);
  }

  function adjustMouseSensitivity(delta) {
    balance.mouseSensitivity = clamp(balance.mouseSensitivity + delta, 0.0012, 0.0042);
    setMessage("Mouse sensitivity " + balance.mouseSensitivity.toFixed(4));
  }

  function restoreTitleScreen() {
    titleScreen.innerHTML = titleScreenMarkup;
    startButton = document.getElementById("startButton");
    startButton.onclick = startGame;
  }

  function createEnemies() {
    return [
      {
        x: 5.5, y: 2.5, alive: true, cooldown: 0, bob: 0.1, patrolIndex: 0, patrolPause: 0,
        strafeDir: 1, strafeTimer: 0, preferredMin: 2.6, preferredMax: 4.6,
        dodgeTimer: 0, dodgeCooldown: 0, dodgeDirX: 0, dodgeDirY: 0,
        patrol: [{ x: 5.5, y: 2.5 }, { x: 6.6, y: 3.4 }, { x: 4.6, y: 5.2 }]
      },
      {
        x: 11.5, y: 5.5, alive: true, cooldown: 0, bob: 1.8, patrolIndex: 0, patrolPause: 0,
        strafeDir: -1, strafeTimer: 0, preferredMin: 2.4, preferredMax: 4.2,
        dodgeTimer: 0, dodgeCooldown: 0, dodgeDirX: 0, dodgeDirY: 0,
        patrol: [{ x: 11.5, y: 5.5 }, { x: 12.8, y: 7.5 }, { x: 9.6, y: 7.4 }]
      },
      {
        x: 12.5, y: 12.5, alive: true, cooldown: 0, bob: 2.7, patrolIndex: 0, patrolPause: 0,
        strafeDir: 1, strafeTimer: 0, preferredMin: 2.8, preferredMax: 4.8,
        dodgeTimer: 0, dodgeCooldown: 0, dodgeDirX: 0, dodgeDirY: 0,
        patrol: [{ x: 12.5, y: 12.5 }, { x: 10.6, y: 13.4 }, { x: 13.4, y: 10.5 }]
      }
    ];
  }

  function createPickups() {
    return [
      { x: 3.5, y: 3.5, taken: false },
      { x: 7.5, y: 9.5, taken: false },
      { x: 13.5, y: 13.5, taken: false }
    ];
  }

  function resetGame() {
    keys = {};
    player = {
      x: 1.8,
      y: 1.8,
      angle: 0,
      hull: 100,
      fuel: 100,
      heat: 0,
      cores: 0,
      shotCooldown: 0
    };
    pickups = createPickups();
    enemies = createEnemies();
    objectiveText.innerHTML = "Collect " + balance.targetCores + " reactor cores, then reach extraction.";
    updateHud();
    setMessage("Click to lock pointer. Press F for fullscreen. Use [ ] to tune aim.");
  }

  function startGame() {
    restoreTitleScreen();
    resetGame();
    state = "playing";
    lastTime = 0;
    mouseLookActive = false;
    lastMouseX = null;
    titleScreen.className = "overlay";
    hud.className = "hud";
    refreshMouseLookState();
    draw();
  }

  function finishGame(success) {
    exitPointerLock();
    mouseLookActive = false;
    lastMouseX = null;
    state = success ? "won" : "lost";
    titleScreen.className = "overlay overlay-visible";
    hud.className = "hud";
    titleScreen.innerHTML =
      '<div class="title-card">' +
      '<p class="eyebrow">District Report</p>' +
      "<h1>" + (success ? "Extraction Clear" : "Operator Down") + "</h1>" +
      '<p class="pitch">' +
      (success
        ? "The run is yours. Restart when you want another dive."
        : "The district held the line. Restart and punch through harder next time.") +
      "</p>" +
      '<div class="feature-grid">' +
      '<div class="feature-box"><span class="feature-label">Cores</span><strong>' + player.cores + " / " + balance.targetCores + "</strong></div>" +
      '<div class="feature-box"><span class="feature-label">Hull</span><strong>' + Math.round(player.hull) + "%</strong></div>" +
      '<div class="feature-box"><span class="feature-label">Fuel</span><strong>' + Math.round(player.fuel) + "%</strong></div>' +
      "</div>" +
      '<div class="controls-box">' +
      '<span class="feature-label">Controls</span>' +
      "<p><span>Move</span><strong>WASD</strong></p>" +
      "<p><span>Look</span><strong>Mouse / Q / E</strong></p>" +
      "<p><span>Fire</span><strong>Space / Click</strong></p>" +
      "<p><span>Display</span><strong>Click + F</strong></p>" +
      "<p><span>Tune Aim</span><strong>[ / ]</strong></p>" +
      "</div>" +
      '<button id="startButton" class="primary-button">Start Run</button>' +
      "</div>";

    startButton = document.getElementById("startButton");
    startButton.onclick = startGame;
  }

  function updateHud() {
    hullBar.style.width = clamp(player.hull, 0, 100) + "%";
    fuelBar.style.width = clamp(player.fuel, 0, 100) + "%";
    heatBar.style.width = clamp(player.heat, 0, 100) + "%";
    hullText.innerHTML = Math.round(clamp(player.hull, 0, 100)) + "%";
    fuelText.innerHTML = Math.round(clamp(player.fuel, 0, 100)) + "%";
    heatText.innerHTML = Math.round(clamp(player.heat, 0, 100)) + "%";
    scrapText.innerHTML = player.cores + " / " + balance.targetCores;
    distanceText.innerHTML = Math.round(distance(player.x, player.y, 3.5, 14.5) * 12) + " m";

    if (player.cores < balance.targetCores) {
      statusText.innerHTML = "Sweep the corridors and secure reactor cores.";
    } else if (player.fuel < 25) {
      statusText.innerHTML = "Extraction ready. Fuel is low, move now.";
    } else {
      statusText.innerHTML = "All cores secured. Reach extraction.";
    }
  }

  function tryFire() {
    var i;
    var bestEnemy = null;
    var bestDistance = Infinity;
    var enemyAngle;
    var angleDiff;
    var dist;

    if (state !== "playing" || player.shotCooldown > 0 || player.heat > 92) {
      return;
    }

    player.shotCooldown = 0.22;
    player.heat = clamp(player.heat + balance.weaponHeatPerShot, 0, 100);
    fireFlash = 0.08;

    for (i = 0; i < enemies.length; i += 1) {
      if (!enemies[i].alive) {
        continue;
      }
      enemyAngle = Math.atan2(enemies[i].y - player.y, enemies[i].x - player.x);
      angleDiff = Math.abs(normalizeAngle(enemyAngle - player.angle));
      dist = distance(player.x, player.y, enemies[i].x, enemies[i].y);

      if (angleDiff < 0.09 && dist < bestDistance && hasLineOfSight(player.x, player.y, enemies[i].x, enemies[i].y)) {
        bestEnemy = enemies[i];
        bestDistance = dist;
      }
    }

    if (bestEnemy) {
      bestEnemy.alive = false;
      setMessage("Drone neutralized.");
    } else {
      setMessage("Shot wide. Recenter and fire again.");
    }
  }

  function hasLineOfSight(ax, ay, bx, by) {
    var dist = distance(ax, ay, bx, by);
    var steps = Math.max(1, Math.floor(dist / 0.05));
    var i;
    for (i = 1; i < steps; i += 1) {
      var t = i / steps;
      var x = ax + (bx - ax) * t;
      var y = ay + (by - ay) * t;
      if (isWall(x, y)) {
        return false;
      }
    }
    return true;
  }

  function enemyBlockedByOthers(enemy, nextX, nextY) {
    var i;
    for (i = 0; i < enemies.length; i += 1) {
      if (enemies[i] === enemy || !enemies[i].alive) {
        continue;
      }
      if (distance(nextX, nextY, enemies[i].x, enemies[i].y) < balance.enemyPersonalSpace) {
        return true;
      }
    }
    return distance(nextX, nextY, player.x, player.y) < balance.enemyPersonalSpace;
  }

  function moveEnemyToward(enemy, targetX, targetY, speed, dt) {
    var dx = targetX - enemy.x;
    var dy = targetY - enemy.y;
    var len = Math.sqrt(dx * dx + dy * dy);
    var moveX;
    var moveY;

    if (len < 0.001) {
      return;
    }

    moveX = (dx / len) * speed * dt;
    moveY = (dy / len) * speed * dt;

    if (Math.abs(moveX) > Math.abs(dx)) {
      moveX = dx;
    }
    if (Math.abs(moveY) > Math.abs(dy)) {
      moveY = dy;
    }

    if (canMoveTo(enemy.x + moveX, enemy.y) && !enemyBlockedByOthers(enemy, enemy.x + moveX, enemy.y)) {
      enemy.x += moveX;
    }
    if (canMoveTo(enemy.x, enemy.y + moveY) && !enemyBlockedByOthers(enemy, enemy.x, enemy.y + moveY)) {
      enemy.y += moveY;
    }
  }

  function moveEnemyBy(enemy, dirX, dirY, speed, dt) {
    moveEnemyToward(enemy, enemy.x + dirX, enemy.y + dirY, speed, dt);
  }

  function resetEnemyStrafe(enemy, preferredDirection) {
    enemy.strafeDir = preferredDirection || (Math.random() < 0.5 ? -1 : 1);
    enemy.strafeTimer = balance.enemyStrafeMinTime +
      Math.random() * (balance.enemyStrafeMaxTime - balance.enemyStrafeMinTime);
  }

  function startEnemyDodge(enemy, baseX, baseY) {
    enemy.dodgeDirX = baseX;
    enemy.dodgeDirY = baseY;
    enemy.dodgeTimer = balance.enemyDodgeDuration;
    enemy.dodgeCooldown = balance.enemyDodgeCooldown + Math.random() * 0.35;
  }

  function updatePlayer(dt) {
    var turn = 0;
    var moveForward = 0;
    var moveSide = 0;
    var speed = keys.Shift ? balance.sprintSpeed : balance.moveSpeed;
    var moveCost = keys.Shift ? balance.sprintFuelDrain : balance.moveFuelDrain;
    var nextX;
    var nextY;

    if (keys.q || keys.ArrowLeft) turn -= 1;
    if (keys.e || keys.ArrowRight) turn += 1;
    if (keys.w) moveForward += 1;
    if (keys.s) moveForward -= 1;
    if (keys.a) moveSide -= 1;
    if (keys.d) moveSide += 1;

    player.angle = normalizeAngle(player.angle + turn * balance.turnSpeed * dt);

    if (moveForward !== 0 || moveSide !== 0) {
      var forwardX = Math.cos(player.angle);
      var forwardY = Math.sin(player.angle);
      var rightX = Math.cos(player.angle + Math.PI / 2);
      var rightY = Math.sin(player.angle + Math.PI / 2);

      nextX = player.x + (forwardX * moveForward * speed + rightX * moveSide * balance.strafeSpeed) * dt;
      nextY = player.y + (forwardY * moveForward * speed + rightY * moveSide * balance.strafeSpeed) * dt;

      if (canMoveTo(nextX, player.y)) {
        player.x = nextX;
      }
      if (canMoveTo(player.x, nextY)) {
        player.y = nextY;
      }

      player.fuel -= moveCost * dt;
    }

    player.fuel -= balance.idleFuelDrain * dt;
    player.heat = clamp(player.heat - balance.weaponHeatCooldown * dt, 0, 100);
    player.fuel = clamp(player.fuel, 0, 100);
    player.shotCooldown = Math.max(0, player.shotCooldown - dt);

    if (keys[" "] || keys.Enter) {
      tryFire();
      keys[" "] = false;
      keys.Enter = false;
    }
  }

  function updatePickups() {
    var i;
    for (i = 0; i < pickups.length; i += 1) {
      if (!pickups[i].taken && distance(player.x, player.y, pickups[i].x, pickups[i].y) < 0.45) {
        pickups[i].taken = true;
        player.cores += 1;
        player.fuel = clamp(player.fuel + balance.pickupFuel, 0, 100);
        player.hull = clamp(player.hull + balance.pickupHull, 0, 100);
        setMessage("Reactor core secured. Rig resupplied.");
      }
    }
  }

  function updateEnemies(dt) {
    var i;
    var dist;
    var hitChance;
    var patrolTarget;
    var seesPlayer;
    var toPlayerX;
    var toPlayerY;
    var lengthToPlayer;
    var normX;
    var normY;
    var strafeX;
    var strafeY;
    var flankTargetX;
    var flankTargetY;

    for (i = 0; i < enemies.length; i += 1) {
      if (!enemies[i].alive) {
        continue;
      }
      dist = distance(player.x, player.y, enemies[i].x, enemies[i].y);
      enemies[i].cooldown = Math.max(0, enemies[i].cooldown - dt);
      enemies[i].dodgeCooldown = Math.max(0, enemies[i].dodgeCooldown - dt);
      seesPlayer = dist < balance.enemyRange && hasLineOfSight(enemies[i].x, enemies[i].y, player.x, player.y);

      if (seesPlayer) {
        toPlayerX = player.x - enemies[i].x;
        toPlayerY = player.y - enemies[i].y;
        lengthToPlayer = Math.max(0.001, Math.sqrt(toPlayerX * toPlayerX + toPlayerY * toPlayerY));
        normX = toPlayerX / lengthToPlayer;
        normY = toPlayerY / lengthToPlayer;
        enemies[i].patrolPause = 0;
        enemies[i].strafeTimer -= dt;

        strafeX = -normY * enemies[i].strafeDir;
        strafeY = normX * enemies[i].strafeDir;

        if (enemies[i].dodgeTimer > 0) {
          moveEnemyBy(enemies[i], enemies[i].dodgeDirX, enemies[i].dodgeDirY, balance.enemyDodgeSpeed, dt);
          enemies[i].dodgeTimer = Math.max(0, enemies[i].dodgeTimer - dt);
        } else if (player.shotCooldown > 0.14 && enemies[i].dodgeCooldown <= 0 && dist < enemies[i].preferredMax + 0.8) {
          startEnemyDodge(
            enemies[i],
            strafeX + (-normX * 0.35),
            strafeY + (-normY * 0.15)
          );
        } else if (dist > enemies[i].preferredMax) {
          moveEnemyToward(enemies[i], player.x, player.y, balance.enemyChaseSpeed, dt);
        } else if (dist < enemies[i].preferredMin) {
          moveEnemyBy(enemies[i], -normX, -normY, balance.enemyRetreatSpeed, dt);
        } else {
          if (enemies[i].strafeTimer <= 0) {
            resetEnemyStrafe(enemies[i]);
          }

          flankTargetX = player.x + strafeX * balance.enemyFlankOffset - normX * 0.65;
          flankTargetY = player.y + strafeY * balance.enemyFlankOffset - normY * 0.65;
          moveEnemyToward(enemies[i], flankTargetX, flankTargetY, balance.enemyFlankSpeed, dt);

          if (!hasLineOfSight(enemies[i].x, enemies[i].y, player.x, player.y)) {
            enemies[i].strafeDir *= -1;
            resetEnemyStrafe(enemies[i], enemies[i].strafeDir);
          }
        }

        if (enemies[i].cooldown <= 0) {
          hitChance = clamp(1 - dist / balance.enemyRange, 0.18, 0.78);
          enemies[i].cooldown = balance.enemyFireDelay + i * 0.08;
          if (Math.random() < hitChance) {
            player.hull -= balance.enemyDamage;
            flashTimer = 0.18;
            setMessage("Taking fire. Break line of sight.");
          } else {
            setMessage("Enemy shot missed. Push or flank.");
          }
        }
      } else {
        enemies[i].patrolPause = Math.max(0, enemies[i].patrolPause - dt);
        enemies[i].strafeTimer = 0;
        enemies[i].dodgeTimer = 0;
        patrolTarget = enemies[i].patrol[enemies[i].patrolIndex];
        if (distance(enemies[i].x, enemies[i].y, patrolTarget.x, patrolTarget.y) < 0.18) {
          if (enemies[i].patrolPause <= 0) {
            enemies[i].patrolIndex = (enemies[i].patrolIndex + 1) % enemies[i].patrol.length;
            enemies[i].patrolPause = balance.enemyPatrolPause;
          }
        } else if (enemies[i].patrolPause <= 0) {
          moveEnemyToward(enemies[i], patrolTarget.x, patrolTarget.y, balance.enemyMoveSpeed, dt);
        }
      }
    }
  }

  function updateWorld(dt) {
    updatePlayer(dt);
    updatePickups();
    updateEnemies(dt);

    if (player.cores >= balance.targetCores && distance(player.x, player.y, 3.5, 14.5) < 0.65) {
      finishGame(true);
      return;
    }

    if (player.hull <= 0 || player.fuel <= 0) {
      finishGame(false);
      return;
    }

    player.hull = clamp(player.hull, 0, 100);
    updateHud();
  }

  function castRay(angle) {
    var depth = 0;
    var hit = false;
    var sampleX = player.x;
    var sampleY = player.y;
    var wallType = "#";

    while (!hit && depth < maxDepth) {
      depth += rayStep;
      sampleX = player.x + Math.cos(angle) * depth;
      sampleY = player.y + Math.sin(angle) * depth;
      if (isWall(sampleX, sampleY)) {
        hit = true;
        wallType = worldMap[Math.floor(sampleY)].charAt(Math.floor(sampleX));
      }
    }

    return {
      distance: depth,
      wallType: wallType
    };
  }

  function renderWalls() {
    var x;
    var rayAngle;
    var ray;
    var correctedDistance;
    var wallHeight;
    var shade;

    ctx.fillStyle = "#24170f";
    ctx.fillRect(0, 0, canvas.width, canvas.height / 2);
    ctx.fillStyle = "#11100f";
    ctx.fillRect(0, canvas.height / 2, canvas.width, canvas.height / 2);

    for (x = 0; x < canvas.width; x += 2) {
      rayAngle = player.angle - fov / 2 + (x / canvas.width) * fov;
      ray = castRay(rayAngle);
      correctedDistance = ray.distance * Math.cos(rayAngle - player.angle);
      correctedDistance = Math.max(0.0001, correctedDistance);
      wallHeight = Math.min(canvas.height, canvas.height / correctedDistance);
      shade = clamp(220 - correctedDistance * 24, 35, 220);

      ctx.fillStyle = "rgb(" + shade + "," + Math.floor(shade * 0.55) + "," + Math.floor(shade * 0.32) + ")";
      ctx.fillRect(
        x,
        (canvas.height - wallHeight) / 2,
        2,
        wallHeight
      );
    }
  }

  function renderSprites() {
    var sprites = [];
    var i;
    var angleTo;
    var dist;
    var relative;
    var screenX;
    var size;
    var screenY;

    for (i = 0; i < pickups.length; i += 1) {
      if (!pickups[i].taken) {
        sprites.push({
          x: pickups[i].x,
          y: pickups[i].y,
          color: "#78d5de",
          accent: "#d8ffff",
          sizeScale: 0.34,
          bob: Math.sin(lastTime / 240 + i) * 0.05
        });
      }
    }

    for (i = 0; i < enemies.length; i += 1) {
      if (enemies[i].alive) {
        sprites.push({
          x: enemies[i].x,
          y: enemies[i].y,
          color: "#ff5a47",
          accent: "#ffd0bf",
          sizeScale: 0.52,
          bob: Math.sin(lastTime / 220 + enemies[i].bob) * 0.08
        });
      }
    }

    sprites.sort(function (a, b) {
      return distance(b.x, b.y, player.x, player.y) - distance(a.x, a.y, player.x, player.y);
    });

    for (i = 0; i < sprites.length; i += 1) {
      angleTo = Math.atan2(sprites[i].y - player.y, sprites[i].x - player.x);
      relative = normalizeAngle(angleTo - player.angle);
      dist = distance(player.x, player.y, sprites[i].x, sprites[i].y);

      if (Math.abs(relative) > fov * 0.65 || !hasLineOfSight(player.x, player.y, sprites[i].x, sprites[i].y)) {
        continue;
      }

      screenX = (0.5 + relative / fov) * canvas.width;
      size = canvas.height / Math.max(0.2, dist) * sprites[i].sizeScale;
      screenY = canvas.height / 2 + sprites[i].bob * 20;

      ctx.fillStyle = sprites[i].color;
      ctx.fillRect(screenX - size / 2, screenY - size / 2, size, size);
      ctx.fillStyle = sprites[i].accent;
      ctx.fillRect(screenX - size / 5, screenY - size / 5, size / 2.5, size / 2.5);
    }
  }

  function renderWeapon() {
    if (fireFlash > 0) {
      ctx.fillStyle = "rgba(255, 205, 122, 0.35)";
      ctx.fillRect(0, 0, canvas.width, canvas.height);
    }

    ctx.fillStyle = "#2e2015";
    ctx.fillRect(canvas.width / 2 - 60, canvas.height - 120, 120, 90);
    ctx.fillStyle = "#ff8d3a";
    ctx.fillRect(canvas.width / 2 + 10, canvas.height - 106, 30, 62);
    ctx.fillStyle = "#f8d1a4";
    ctx.fillRect(canvas.width / 2 + 30, canvas.height - 92, 22, 18);
  }

  function renderCrosshair() {
    ctx.strokeStyle = player.heat > 85 ? "#ff5a47" : "#f6e7d0";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(canvas.width / 2 - 12, canvas.height / 2);
    ctx.lineTo(canvas.width / 2 - 2, canvas.height / 2);
    ctx.moveTo(canvas.width / 2 + 2, canvas.height / 2);
    ctx.lineTo(canvas.width / 2 + 12, canvas.height / 2);
    ctx.moveTo(canvas.width / 2, canvas.height / 2 - 12);
    ctx.lineTo(canvas.width / 2, canvas.height / 2 - 2);
    ctx.moveTo(canvas.width / 2, canvas.height / 2 + 2);
    ctx.lineTo(canvas.width / 2, canvas.height / 2 + 12);
    ctx.stroke();
  }

  function renderDamageFlash() {
    if (flashTimer > 0) {
      ctx.fillStyle = "rgba(255, 72, 56, " + clamp(flashTimer / 0.18, 0, 0.28) + ")";
      ctx.fillRect(0, 0, canvas.width, canvas.height);
    }
  }

  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    renderWalls();
    renderSprites();
    renderWeapon();
    renderCrosshair();
    renderDamageFlash();
  }

  function tick(timestamp) {
    var dt = (timestamp - lastTime) / 1000;
    if (!lastTime || dt > 0.1) {
      dt = 0.016;
    }
    lastTime = timestamp;

    if (state === "playing") {
      updateWorld(dt);
    }

    draw();

    if (messageTimer > 0) {
      messageTimer -= dt;
      if (messageTimer <= 0) {
        messageOverlay.className = "message-overlay hidden";
        lastMessage = "";
      }
    }

    flashTimer = Math.max(0, flashTimer - dt);
    fireFlash = Math.max(0, fireFlash - dt);
    window.requestAnimationFrame(tick);
  }

  document.addEventListener("keydown", function (event) {
    keys[event.key] = true;
    if (event.key === "[" || event.key === "{") {
      adjustMouseSensitivity(-0.00025);
    }
    if (event.key === "]" || event.key === "}") {
      adjustMouseSensitivity(0.00025);
    }
    if (event.key === "f" || event.key === "F") {
      toggleFullscreen();
      setMessage("Fullscreen toggle requested.");
    }
    if (event.key === "r" || event.key === "R") {
      startGame();
    }
  });

  document.addEventListener("keyup", function (event) {
    keys[event.key] = false;
  });

  document.addEventListener("pointerlockchange", refreshMouseLookState);
  document.addEventListener("mozpointerlockchange", refreshMouseLookState);
  document.addEventListener("webkitpointerlockchange", refreshMouseLookState);
  document.addEventListener("mspointerlockchange", refreshMouseLookState);
  document.addEventListener("fullscreenchange", refreshFullscreenState);
  document.addEventListener("webkitfullscreenchange", refreshFullscreenState);
  document.addEventListener("mozfullscreenchange", refreshFullscreenState);
  document.addEventListener("MSFullscreenChange", refreshFullscreenState);

  canvas.addEventListener("mousedown", function (event) {
    if (state !== "playing") {
      return;
    }

    if (pointerLockSupported && !pointerLocked) {
      requestPointerLock();
      setMessage("Pointer lock requested. Press Esc to release.");
    }

    if (!pointerLocked) {
      mouseLookActive = true;
      lastMouseX = event.clientX;
      refreshMouseLookState();
    }

    if (event.button === 0) {
      tryFire();
    }
  });

  document.addEventListener("mouseup", function () {
    if (!pointerLocked) {
      mouseLookActive = false;
      lastMouseX = null;
      refreshMouseLookState();
    }
  });

  canvas.addEventListener("mousemove", function (event) {
    var deltaX = event.movementX || event.mozMovementX || event.webkitMovementX || 0;

    if (pointerLocked) {
      applyMouseLook(deltaX);
      return;
    }

    if (!deltaX && mouseLookActive && lastMouseX !== null) {
      deltaX = event.clientX - lastMouseX;
    }

    lastMouseX = event.clientX;
    if (mouseLookActive || deltaX) {
      applyMouseLook(deltaX);
    }
  });

  canvas.addEventListener("mouseleave", function () {
    if (!pointerLocked) {
      mouseLookActive = false;
      lastMouseX = null;
      refreshMouseLookState();
    }
  });

  canvas.addEventListener("contextmenu", function (event) {
    event.preventDefault();
  });

  startButton.onclick = startGame;
  refreshMouseLookState();
  draw();
  window.requestAnimationFrame(tick);
})();
