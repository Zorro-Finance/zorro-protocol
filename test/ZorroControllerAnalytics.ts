const ZorroController = artifacts.require('ZorroController');

// TODO: This is a placeholder 
contract('ZorroController', async accounts => {
    it('should show pending Zorro rewards', async () => {
        const instance = await ZorroController.deployed();
        // assert.equal(true, true);
    })
})