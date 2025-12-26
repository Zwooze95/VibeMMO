import Arena from "@colyseus/arena";
import { monitor } from "@colyseus/monitor";

/**
 * Import your Room files
 */
import { MyRoom } from "./src/rooms/MyRoom";

export default Arena({
    initializeExpress: (app) => {
        app.use("/colyseus", monitor());
    },

    initializeGameServer: (gameServer) => {
        /**
         * Define your room handlers:
         */
        gameServer.define('my_room', MyRoom)
            .enableRealtimeListing()
            // Increase reservation timeout to 30 seconds (default is 3-5 seconds)
            .filterBy(['any']);
    },

    beforeListen: () => {
        /**
         * Before before gameServer.listen() is called.
         */
    }
} as any);
