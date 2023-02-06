// ZorroControllerXChainActions contract
// Includes all tests for ZorroControllerXChain contract utilities

contract('ZorroControllerXChainActions :: Utilities', async accounts => {
    it('Converts raw bytes to an EVM address', async () => {
        /* GIVEN
        - A raw bytes encoded EVM address
        */

        /* WHEN
        - Calling bytesToAddress()
        */

        /* THEN
        - I should receive a valid address equivalent to what I put in
        */
    });

    it('Strips the function signature from a raw bytes payload with signature', async () => {
        /* GIVEN
        - An ABI encoded payload with function signature
        */

        /* WHEN
        - Calling extractParamsPayload()
        */

        /* THEN
        - I should receive a bytes array with the signature removed (i.e. just the payload)
        */
    });
});

contract('ZorroControllerXChainActions :: Deposits', async accounts => {
    it('Checks with Stargate to determine how much fees a deposit will cost', async () => {
        /* GIVEN
        - A destination contract, chain, and payload
        */

        /* WHEN
        - Calling checkXChainDepositFee()
        */

        /* THEN
        - I should receive the fee required to make the deposit
        */
    });

    it('Encodes cross-chain deposit instructions into a bytes payload', async () => {
        /* GIVEN
        - Vault parameters
        */

        /* WHEN
        - Calling encodeXChainDepositPayload()
        */

        /* THEN
        - A valid bytes payload is calculated
        */
    });
});

contract('ZorroControllerXChainActions :: EarningsDistribution', async accounts => {
    it('Checks with Stargate to determine how much fees an earnings distribution will cost', async () => {
        /* GIVEN
        - A destination contract, chain, and payload
        */

        /* WHEN
        - Calling checkXChainDistributeEarningsFee()
        */

        /* THEN
        - I should receive the fee required to make the earnings distribution
        */
    });

    it('Encodes cross-chain earnings distribution instructions into a bytes payload', async () => {
        /* GIVEN
        - Vault parameters
        */

        /* WHEN
        - Calling encodeXChainDistributeEarningsPayload()
        */

        /* THEN
        - A valid bytes payload is calculated
        */
    });

    it('Receives and fulfills an earnings distribution request', async () => {
        /* GIVEN
        - Buyback and revshare parameters
        */

        /* WHEN
        - Calling distributeEarnings()
        */

        /* THEN
        - Funds are transferred from the sender
        - On chain buyback is executed for the correct amount
        - On chain revshare is executed for the correct amount
        */

        // TODO: Expect buyback, revshare, etc.
    });
});

contract('ZorroControllerXChainActions :: Withdrawals', async accounts => {
    it('Checks with Stargate to determine how much fees a withdrawal will cost', async () => {
        /* GIVEN
        - A destination contract, chain, and payload
        */

        /* WHEN
        - Calling checkXChainWithdrawalFee()
        */

        /* THEN
        - I should receive the fee required to make the withdrawal
        */
    });

    it('Encodes cross-chain withdrawal instructions into a bytes payload', async () => {
        /* GIVEN
        - Trache and account parameters
        */

        /* WHEN
        - Calling encodeXChainWithdrawalPayload()
        */

        /* THEN
        - Receive a valid bytes payload
        */
    });

    it('Checks with Stargate to determine how much fees a repatriation will cost', async () => {
        /* GIVEN
        - A destination contract and payload
        */

        /* WHEN
        - Calling checkXChainRepatriationFee()
        */

        /* THEN
        - A fee from Stargate is obtained
        */
    });

    it('Encodes cross-chain repatriation instructions into a bytes payload', async () => {
        /* GIVEN
        */

        /* WHEN
        */

        /* THEN
        */
    });
});
