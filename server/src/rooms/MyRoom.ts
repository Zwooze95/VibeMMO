import { Room, Client } from "colyseus";

// Protokoll-definitioner
const OP = {
    JOIN: 0,
    MOVE: 1,
    LEAVE: 2,
    ENEMY_SPAWN: 3,
    ENEMY_DEATH: 4,
    COLYSEUS_JOIN_ROOM: 10, //COLYSEUS BUILT IN, NEVER USE THESE ONLY FOR TAKING INT
    COLYSEUS_JOIN_ERROR: 11, //COLYSEUS BUILT IN, NEVER USE THESE ONLY FOR TAKING INT
    COLYSEUS_LEAVE_ROOM: 12 //COLYSEUS BUILT IN, NEVER USE THESE ONLY FOR TAKING INT
};

export class MyRoom extends Room {
    // Vi håller koll på nästa lediga ID
    nextPlayerId = 1;

    // Enemy management
    nextEnemyId = 1;
    enemies: any = {}; // { enemyId: { x, y, type } }
    maxEnemies = 5;
    spawnAreaSize = { x: 20, z: 20 };
    spawnInterval: any = null;

    // Map för att översätta SessionID (sträng) -> PlayerID (siffra)
    players: any = {}; // { sessionId: { pId: 1, x: 0, y: 0 } }

    onCreate(options: any) {
        // VIKTIGT: Vi använder INTE Colyseus onMessage för game messages
        // Istället lyssnar vi direkt på raw WebSocket messages

        this.onMessage("*", (client, type, message) => {
            // Fånga alla Colyseus messages vi inte hanterar
            console.log(`[MyRoom] Unhandled Colyseus message: ${type}`, message);
        });

        // Starta enemy spawning
        this.startEnemySpawning();
    }

    onJoin(client: Client) {
        const pId = this.nextPlayerId++;
        this.players[client.sessionId] = { pId: pId, x: 0, y: 0 };

        console.log(`Spelare joinade. Tilldelad ID: ${pId}`);

        // Lyssna på RAW WebSocket messages (utanför Colyseus protokoll)
        const ws = (client as any).ref;
        ws.on('message', (data: Buffer | string) => {
            // Om det är binär data
            if (Buffer.isBuffer(data)) {
                this.handleRawBinaryMessage(client, data);
            }
            // Colyseus hanterar text messages via sitt eget system
        });

        // 1. Skicka "Welcome" (Vem är jag?) - Skicka som RAW text
        const welcomeMsg = JSON.stringify(["welcome", { myId: pId }]);
        if (ws.readyState === 1) {
            ws.send(welcomeMsg);
        }

        // 2. Skicka BINÄRT "Join" till alla andra
        this.broadcastBinary(OP.JOIN, pId, 0, 0);

        // 3. Skicka existerande spelare till den nya (Binärt)
        for (let sid in this.players) {
            if (sid !== client.sessionId) {
                const p = this.players[sid];
                this.sendBinaryTo(client, OP.JOIN, p.pId, p.x, p.y);
            }
        }

        // 4. Skicka existerande fiender till den nya spelaren
        for (let enemyId in this.enemies) {
            const enemy = this.enemies[enemyId];
            this.sendEnemySpawnTo(client, parseInt(enemyId), enemy.x, enemy.y, enemy.type);
        }
    }

    // Hantera raw binära meddelanden från klienter
    handleRawBinaryMessage(client: Client, buffer: Buffer) {
        if (buffer.length < 1) return;

        const opCode = buffer.readUInt8(0);

        switch (opCode) {
            case OP.MOVE:
                if (buffer.length < 9) {
                    console.log(`[MyRoom] MOVE packet too short: ${buffer.length} bytes`);
                    return;
                }
                const x = buffer.readFloatLE(1);
                const y = buffer.readFloatLE(5);

                const player = this.players[client.sessionId];
                if (player) {
                    player.x = x;
                    player.y = y;
                    // Broadcast to all
                    this.broadcastMove(player.pId, player.x, player.y);
                }
                break;

            default:
                console.log(`[MyRoom] Unknown raw opcode: ${opCode}`);
        }
    }

    onLeave(client: Client) {
        const player = this.players[client.sessionId];
        if (player) {
            // Skicka binärt LEAVE
            this.broadcastLeave(player.pId);
            delete this.players[client.sessionId];
        }
    }

    onDispose() {
        // Rensa spawn timer
        if (this.spawnInterval) {
            clearInterval(this.spawnInterval);
        }
    }

    // --- ENEMY MANAGEMENT ---

    startEnemySpawning() {
        console.log("[MyRoom] Starting enemy spawning system");
        // Spawna initiala fiender
        this.spawnEnemiesIfNeeded();

        // Spawna nya fiender var 3:e sekund
        this.spawnInterval = setInterval(() => {
            this.spawnEnemiesIfNeeded();
        }, 3000);
    }

    spawnEnemiesIfNeeded() {
        const enemyCount = Object.keys(this.enemies).length;
        if (enemyCount < this.maxEnemies) {
            const x = (Math.random() - 0.5) * this.spawnAreaSize.x;
            const y = (Math.random() - 0.5) * this.spawnAreaSize.z;
            const enemyId = this.nextEnemyId++;
            const enemyType = Math.floor(Math.random() * 3); // 0-2 för olika enemy types

            this.enemies[enemyId] = { x, y, type: enemyType };
            console.log(`[MyRoom] Spawned enemy ${enemyId} at (${x.toFixed(2)}, ${y.toFixed(2)}), type: ${enemyType}`);

            // Broadcasta till alla klienter
            this.broadcastEnemySpawn(enemyId, x, y, enemyType);
        }
    }

    // --- BINÄRA HJÄLPFUNKTIONER ---

    broadcastMove(pId: number, x: number, y: number) {
        // Skapa buffert: 1 byte (OP) + 2 bytes (ID) + 4 bytes (X) + 4 bytes (Y) = 11
        const buffer = Buffer.alloc(11);
        buffer.writeUInt8(OP.MOVE, 0);      // Index 0
        buffer.writeUInt16LE(pId, 1);       // Index 1 (Little Endian)
        buffer.writeFloatLE(x, 3);          // Index 3
        buffer.writeFloatLE(y, 7);          // Index 7

        this.broadcastRaw(buffer);
    }

    broadcastBinary(op: number, pId: number, x: number, y: number) {
        const buffer = Buffer.alloc(11);
        buffer.writeUInt8(op, 0);
        buffer.writeUInt16LE(pId, 1);
        buffer.writeFloatLE(x, 3);
        buffer.writeFloatLE(y, 7);
        this.broadcastRaw(buffer);
    }

    broadcastLeave(pId: number) {
        const buffer = Buffer.alloc(3); // OP + ID
        buffer.writeUInt8(OP.LEAVE, 0);
        buffer.writeUInt16LE(pId, 1);
        this.broadcastRaw(buffer);
    }

    // Generisk funktion för att skicka rå buffert
    broadcastRaw(buffer: Buffer) {
        this.clients.forEach(c => {
            if ((c as any).ref.readyState === 1) {
                (c as any).ref.send(buffer);
            }
        });
    }

    sendBinaryTo(client: Client, op: number, pId: number, x: number, y: number) {
        const buffer = Buffer.alloc(11);
        buffer.writeUInt8(op, 0);
        buffer.writeUInt16LE(pId, 1);
        buffer.writeFloatLE(x, 3);
        buffer.writeFloatLE(y, 7);
        if ((client as any).ref.readyState === 1) {
            (client as any).ref.send(buffer);
        }
    }

    broadcastEnemySpawn(enemyId: number, x: number, y: number, type: number) {
        // ENEMY_SPAWN: 1 byte (OP) + 4 bytes (ID) + 4 bytes (X) + 4 bytes (Y) + 1 byte (type) = 14
        const buffer = Buffer.alloc(14);
        buffer.writeUInt8(OP.ENEMY_SPAWN, 0);
        buffer.writeUInt32LE(enemyId, 1);
        buffer.writeFloatLE(x, 5);
        buffer.writeFloatLE(y, 9);
        buffer.writeUInt8(type, 13);
        this.broadcastRaw(buffer);
    }

    broadcastEnemyDeath(enemyId: number) {
        // ENEMY_DEATH: 1 byte (OP) + 4 bytes (ID) = 5
        const buffer = Buffer.alloc(5);
        buffer.writeUInt8(OP.ENEMY_DEATH, 0);
        buffer.writeUInt32LE(enemyId, 1);
        this.broadcastRaw(buffer);
    }

    sendEnemySpawnTo(client: Client, enemyId: number, x: number, y: number, type: number) {
        // Skicka ENEMY_SPAWN till en specifik klient
        const buffer = Buffer.alloc(14);
        buffer.writeUInt8(OP.ENEMY_SPAWN, 0);
        buffer.writeUInt32LE(enemyId, 1);
        buffer.writeFloatLE(x, 5);
        buffer.writeFloatLE(y, 9);
        buffer.writeUInt8(type, 13);
        if ((client as any).ref.readyState === 1) {
            (client as any).ref.send(buffer);
        }
    }
}