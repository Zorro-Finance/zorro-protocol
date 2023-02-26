// TeamVestingWallet contract
// Includes all tests for Zorro team vesting wallets (used by team members and advisors)

contract('TeamVestingWallet', async accounts => {
    xit('It releases vested funds once cliff has been reached', async () => {
        /* GIVEN
        - As the beneficiary of the vesting wallet
        - The cliff has been reached
        */

        /* WHEN
        - I attempt to release the vested funds after X elapsed time
        */

        /* THEN
        - The vested amount is transferred to me
        */
    });

    xit('It does not release any funds until cliff has been reached', async () => {
        /* GIVEN
        - As the beneficiary of the vesting wallet
        - The cliff has NOT been reached
        */

        /* WHEN
        - I attempt to release the vested funds after X elapsed time
        */

        /* THEN
        - I expect to not receive any funds
        */
    });
});