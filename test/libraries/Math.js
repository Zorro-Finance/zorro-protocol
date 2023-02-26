const MockCustomMath = artifacts.require('MockCustomMath');

contract('Math', async accounts => {
    xit('calculates the square root to reasonable accuracy', async () => {
        const lib = await MockCustomMath.new();

        const factor = 1e4;
        const precision = 0.1;

        assert.equal(await lib.sqrt.call(0), 0);
        assert.equal(await lib.sqrt.call(1), 1);
        assert.approximately(await lib.sqrt.call(2*factor)/Math.sqrt(factor), precision, 1.41);
        assert.equal(await lib.sqrt.call(4), 2);
        assert.approximately(await lib.sqrt.call(6*factor)/Math.sqrt(factor), precision, 2.449);
        assert.approximately(await lib.sqrt.call(12*factor)/Math.sqrt(factor), precision, 3.464);
        assert.approximately(await lib.sqrt.call(17*factor)/Math.sqrt(factor), precision, 4.123);
        assert.approximately(await lib.sqrt.call(24*factor)/Math.sqrt(factor), precision, 4.899);
    });
})