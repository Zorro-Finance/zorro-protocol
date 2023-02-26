// Zorro contract
// Includes all tests for Zorro token

contract('Zorro :: Setters', async accounts => {
    xit('Sets the Zorro Controller address', async () => {
        /* GIVEN
        - As the owner (timelock executor) of the Zorro contract
        */

        /* WHEN
        - I set the Zorro Controller address
        */

        /* THEN
        - The Zorro controller address gets updated
        */
    });
});

contract('Zorro :: Finance', async accounts => {
    xit('Mints tokens (only when called by Zorro Controller)', async () => {
        /* GIVEN
        - A Zorro contract with a Zorro Controller address set
        - As the Zorro Controller, and ONLY the Zorro controller
        */

        /* WHEN
        - I attempt to mint ZOR tokens
        */

        /* THEN
        - ZOR tokens are minted and ONLY sent to the Zorro controller
        */
    });
});