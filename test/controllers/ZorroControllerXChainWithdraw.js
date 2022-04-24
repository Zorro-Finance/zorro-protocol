const MockZorroController = artifacts.require('MockZorroController');

contract('ZorroController', async accounts => {
    let instance;

    before(async () => {
        instance = await MockZorroController.deployed();
    });

    xit('checks X chain withdrawal fee', async () => {

    });
    
    xit('gets LZ adapter params', async () => {
        
    });

    xit('checks X chain Repatriation fee', async () => {
        
    });

    xit('encodes X chain withdrawal payload', async () => {
        
    });

    xit('sends X chain withdrawal request', async () => {
        // Check auth
    });

    xit('sends X chain repatriation request', async () => {
        // Check auth
    });

    xit('receives X chain withdrawal request', async () => {
        // Check auth
    });

    xit('receives X chain repatriation request', async () => {
        // Check auth
    });
})