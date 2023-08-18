import * as fs from 'fs';
import * as path from 'path';

function checkNode(_root: any, _list: any[] = []): void {
    if (_root === null || _root === undefined) {
      return; // Exit the function if _root is null or undefined
    }
    if (typeof _root === 'object') {
      if (_root.nodeType === 'ErrorDefinition') {
        _list.push(_root);
      }
      if (Array.isArray(_root)) {
        _root.forEach(value => checkNode(value, _list));
      } else {
        Object.values(_root).forEach(value => checkNode(value, _list));
      }
    }
  }
  

function getFiles(dirPath: string, extension: string, fileList: string[] = []): string[] {
  const files = fs.readdirSync(dirPath);
  files.forEach(file => {
    if (fs.statSync(path.join(dirPath, file)).isDirectory()) {
      fileList = getFiles(path.join(dirPath, file), extension, fileList);
    } else {
      if (path.extname(file) === extension) {
        fileList.push(path.join(dirPath, file));
      }
    }
  });
  return fileList;
}

let df: any[] = [];
const pathlist = getFiles('./out', '.json');

pathlist.forEach(filePath => {
  console.log(filePath);
  const content = fs.readFileSync(filePath, 'utf8');
  const ast = JSON.parse(content);
  const nodes: any[] = [];
  checkNode(ast, nodes);

  // deduplicate and format
  nodes.forEach(node => {
    if (!df.find(d => d.errorSelector === node.errorSelector)) {
      if (node.errorSelector) {
        df.push({ errorSelector: node.errorSelector, name: node.name, parameters: node.parameters });
      } else {
        df.push(node);
      }
    }
  });
});

// clean custom error parameters
df = df.map(row => ({
    ...row,
    parameters: Array.isArray(row.parameters) ? row.parameters.map((x: any) => ({ name: x.name, type: x.typeName.name })) : undefined,
}));
  

console.log(df);
fs.writeFileSync('./errors.json', JSON.stringify(df, null, 2));
