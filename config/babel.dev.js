module.exports = {
    babelrc: false,
    cacheDirectory: true,
    presets: [
        'babel-preset-env',
        'babel-preset-react',
        'babel-preset-stage-0'
    ].map(require.resolve),
    plugins: [
        'babel-plugin-syntax-trailing-function-commas',
        'babel-plugin-transform-decorators-legacy',
        'babel-plugin-transform-class-properties',
        'babel-plugin-transform-object-rest-spread'
    ].map(require.resolve).concat([
        [require.resolve('babel-plugin-transform-runtime'), {
            helpers: false,
            polyfill: false,
            regenerator: true
        }]
    ])
};
