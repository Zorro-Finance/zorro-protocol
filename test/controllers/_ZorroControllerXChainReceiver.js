// ZorroControllerXChainReceiver contract
// Includes all tests for receiving cross chain events

contract('ZorroControllerXChainReceiver :: Receivers', async accounts => {
    it('Receives Stargate deposit message', async () => {
        /* GIVEN
        - As a registered cross chain controller
        */

        /* WHEN
        - A deposit message is received from Stargate
        */

        /* THEN
        - A full service deposit should occur
        */
    });

    it('Receives Stargate repatriation message', async () => {
        /* GIVEN
        - As a registered cross chain controller
        */

        /* WHEN
        - A repatriation message is received from Stargate
        */

        /* THEN
        - A Repatriation event should be emitted
        */
    });

    it('Receives Stargate earnings distribution message', async () => {
        /* GIVEN
        - As a registered cross chain controller
        */

        /* WHEN
        - A repatriation message is received from Stargate
        */

        /* THEN
        - A XChainDistributeEarnings event should be emitted
        */
    });

    it('Receives LayerZero message', async () => {
        /* GIVEN
        - As a registered cross chain controller
        */

        /* WHEN
        - A repatriation message is received from LayerZero
        */

        /* THEN
        - A full service withdrawal should occur
        */
    });
});