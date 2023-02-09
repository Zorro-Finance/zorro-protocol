exports.getSynthNetwork = (network) => {
  if (network === 'avaxfork') {
    return 'avax';
  }

  if (network === 'bnbfork') {
    return 'bnb';
  }

  return network;
};

exports.isTestNetwork = (network) => network.includes('test');
exports.isDevNetwork = (network) => network.includes('fork') || network.includes('test');