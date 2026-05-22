const path = require('path');

const BUILD_DIR = path.join(__dirname, 'dist');
const CLIENTLIB_DIR = path.join(
  __dirname,
  '..',
  'ui.apps',
  'src',
  'main',
  'content',
  'jcr_root',
  'apps',
  'spa-mvn',
  'clientlibs'
);

module.exports = {
  context: BUILD_DIR,
  clientLibRoot: CLIENTLIB_DIR,
  libs: [
    {
      allowProxy: true,
      serializationFormat: 'xml',
      cssProcessor: ['default:none', 'min:none'],
      jsProcessor: ['default:none', 'min:none'],
      name: 'clientlib-site',
      categories: ['spa-mvn.site'],
      assets: {
        js: {
          cwd: 'clientlib-site/js',
          files: ['**/*.js'],
          flatten: false
        },
        css: {
          cwd: 'clientlib-site/css',
          files: ['**/*.css'],
          flatten: false
        }
      }
    }
  ]
};
