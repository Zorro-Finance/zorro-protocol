exports.getSynthNetwork = (network) => {
  if (network === 'avaxfork') {
    return 'avax';
  }

  if (network === 'bnbfork') {
    return 'bnb';
  }

  return network;
};

exports.isTestNetwork = (network) => network.includes('fork');