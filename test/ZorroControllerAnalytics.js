const ZorroController = artifacts.require('ZorroController');


contract('ZorroController', async accounts => {
    it('should show pending Zorro rewards', async () => {
        const instance = await ZorroController.deployed();
        // assert.equal(true, true);
    });
    
    it('should show the amt Want tokens staked', async () => {

    });
})