const MockPriceFeed = artifacts.require('MockPriceFeed');
const MockAggregatorV3 = artifacts.require('MockAggregatorV3');

contract('MockPriceFeed', async accounts => {
    it('gets the exchange rate for a given price feed', async () => {
        const price = 1.578e12;
        const dec = 3;

        const lib = await MockPriceFeed.deployed();
        const priceFeed = await MockAggregatorV3.deployed(); 
        await priceFeed.setDecimals.call(dec);
        await priceFeed.setAnswer.call(price);
        const ans = await lib.getExchangeRate.call(priceFeed.address);

        assert.equal(ans, price * (1e12) / (10**dec));
    });
})