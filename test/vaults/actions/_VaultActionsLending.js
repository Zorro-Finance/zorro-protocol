// VaultActionsLending tests
// Test for common utilities functions of lending vaults

contract('VaultActionsLending :: Analytics', async accounts => {
    xit('Calculates current want equity', async () => {
        /* GIVEN
        - As a public user
        */

        /* WHEN
        - I query the current want equity
        */

        /* THEN
        - I receive the current unrealized position value in Want token units
        */
    });

    xit('Calculates leveraged lending parameters', async () => {
        /* GIVEN
        - As a public user
        - Withdrawal amount, supply of underlying pool, comptroller address, 
        pool address, target borrow limit
        */

        /* WHEN
        - Calling levLendingParams()
        */

        /* THEN
        - I get the following quantities: Adjusted supply, amount borrowed, 
        collateral factor, target leverage threshold, current leverage, and liquidity available
        */
    });

    xit('Calculates incremental borrow amount when below leverage target', async () => {
        /* GIVEN
        - As a vault
        - My total leverage position for a lending pool is under the target leverage threshold
        */

        /* WHEN
        - Calling calcIncBorrowBelowTarget
        */

        /* THEN
        - It returns the incremental amount I need to borrow to get into the target leverage hysteresis envelope
        */
    });

    xit('Calculates incremental over-borrow amount when above leverage target', async () => {
        /* GIVEN
        - As a vault
        - My total leverage position for a lending pool is over the target leverage threshold
        */

        /* WHEN
        - Calling calcIncBorrowAboveTarget
        */

        /* THEN
        - It returns the incremental amount I need to borrow to get into the target leverage hysteresis envelope
        */
    });

    xit('Calculates adjusted want token quantity, accounting for supply/borrow position', async () => {
        /* GIVEN
        - As a public user 
        */

        /* WHEN
        - I query the want token locked amount
        */

        /* THEN
        - I expect to receive the difference between the total amount supplied and borrowed, plus any want token balance on the vault contract
        */
    });
});