import {createRequire} from 'node:module';
import {writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const require=createRequire(process.cwd()+'/package.json');
const ranks=require('js-tiktoken/ranks/o200k_base');
// Revisit resource provenance and cross-language vectors before changing this version.
const packageURL=new URL('../package.json', 'file://'+require.resolve('js-tiktoken/lite'));
const {readFileSync}=await import('node:fs');
if(JSON.parse(readFileSync(packageURL,'utf8')).version!=='1.0.21')throw Error('Review the native tokenizer before generating from another js-tiktoken version');
const tokens=[];
for(const line of ranks.bpe_ranks.split('\n').filter(Boolean)) {
 const [,offset,...entries]=line.split(' ');
 entries.forEach((token,i)=>{tokens[Number(offset)+i]=Buffer.from(token,'base64');});
}
if(tokens.length!==199998||tokens.some(x=>!x?.length||x.length>65535))throw Error('Unsupported o200k_base rank table');
const header=Buffer.alloc(12);header.write('ZTOK200K');header.writeUInt32LE(tokens.length,8);
const parts=[header];for(const token of tokens){const size=Buffer.alloc(2);size.writeUInt16LE(token.length);parts.push(size,token);}
const binary=Buffer.concat(parts);
const destination=process.argv[2]??'native-ios/Resources';
writeFileSync(destination+'/NativeO200k.bin',binary);
writeFileSync(destination+'/NativeO200k.json',JSON.stringify({version:1,encoding:'o200k_base',source:'js-tiktoken 1.0.21',sha256:createHash('sha256').update(binary).digest('hex'),count:tokens.length,pattern:ranks.pat_str},null,2)+'\n');
console.log(JSON.stringify({tokens:tokens.length,bytes:binary.length,sha256:createHash('sha256').update(binary).digest('hex')}));
