import { Room, Client } from "colyseus";

// Protokoll-definitioner
const OP = {
    JOIN: 1,
    MOVE: 2,
    LEAVE: 3
};

export class MyRoom extends Room {
    // Vi håller koll på nästa lediga ID
    nextPlayerId = 1;

    // Map för att översätta SessionID (sträng) -> PlayerID (siffra)
    players: any = {}; // { sessionId: { pId: 1, x: 0, y: 0 } }

    onCreate(options: any) {
        // Ta emot JSON "move" (för bakåtkompatibilitet)
        this.onMessage("move", (client, data) => {
            const player = this.players[client.sessionId];
            if (player) {
                player.x = data.x;
                player.y = data.y;
                // Skicka binär uppdatering till alla
                this.broadcastMove(player.pId, player.x, player.y);
            }
        });

        // Ta emot BINÄR "move" från klienten
        this.onMessage(0, (client, bytes: ArrayBuffer | number[]) => {
            // Konvertera till Buffer om det behövs
            const buffer = Buffer.from(bytes as any);

            // Validera längd (1 byte OP + 4 bytes X + 4 bytes Y = 9 bytes)
            if (buffer.length < 9) {
                console.log(`[MyRoom] Binärt move-paket för kort: ${buffer.length} bytes`);
                return;
            }

            // Läs data
            const opCode = buffer.readUInt8(0);

            // Kolla att det är MOVE (2)
            if (opCode !== OP.MOVE) {
                console.log(`[MyRoom] Binärt paket har fel OpCode: ${opCode}`);
                return;
            }

            const x = buffer.readFloatLE(1);  // Börja på byte 1
            const y = buffer.readFloatLE(5);  // Börja på byte 5

            const player = this.players[client.sessionId];
            if (player) {
                player.x = x;
                player.y = y;
                console.log(`[MyRoom] Binär move från ID ${player.pId}: X=${x.toFixed(2)}, Y=${y.toFixed(2)}`);
                // Skicka binär uppdatering till alla
                this.broadcastMove(player.pId, player.x, player.y);
            }
        });
    }

    onJoin(client: Client) {
        const pId = this.nextPlayerId++;
        this.players[client.sessionId] = { pId: pId, x: 0, y: 0 };

        console.log(`Spelare joinade. Tilldelad ID: ${pId}`);

        // 1. Skicka "Welcome" (Vem är jag?) - Detta kan vara JSON för enkelhetens skull
        client.send(JSON.stringify({ type: "welcome", myId: pId }));

        // 2. Skicka BINÄRT "Join" till alla andra
        this.broadcastBinary(OP.JOIN, pId, 0, 0);

        // 3. Skicka existerande spelare till den nya (Binärt)
        for (let sid in this.players) {
            if (sid !== client.sessionId) {
                const p = this.players[sid];
                this.sendBinaryTo(client, OP.JOIN, p.pId, p.x, p.y);
            }
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
}