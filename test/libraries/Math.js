const MockCustomMath = artifacts.require('MockCustomMath');

contract('MockCustomMath', async accounts => {
    it('calculates the square root to reasonable accuracy', async () => {
        let lib = await MockCustomMath.deployed();

        const ans0 = await lib.sqrt.call(64);
        assert.equal(ans0, 8);

        const ans1 = await lib.sqrt.call(0);
        assert.equal(ans1, 0);

        const ans2 = await lib.sqrt.call(1000);
        assert.equal(ans2, Math.sqrt(1000));
    });
})