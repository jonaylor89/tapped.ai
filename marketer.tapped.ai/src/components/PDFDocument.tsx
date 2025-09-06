/* eslint-disable sonarjs/cognitive-complexity */
import React from 'react';
import { Page, Text, View, Document, StyleSheet, Image } from '@react-pdf/renderer';
import MarkdownIt from 'markdown-it';
import { Rubik } from 'next/font/google';

const rubik = Rubik({
  subsets: ['latin'],
  weight: ['300', '400', '500', '600', '700', '800', '900'],
});

const md = new MarkdownIt();

const styles = StyleSheet.create({
  page: {
    backgroundColor: '#15242d',
    paddingTop: 80,
    paddingRight: 80,
    paddingBottom: 80,
    paddingLeft: 80,
  },
  header1: {
    fontSize: 40,
    fontWeight: 900,
    marginBottom: 20,
    marginTop: 15,
    color: 'white',
  },
  header2: {
    fontSize: 20,
    fontWeight: 'bold',
    marginBottom: 15,
    marginTop: 15,
    color: 'white',
  },
  text: {
    marginBottom: 10,
    color: 'white',
  },
  bulletList: {
    marginBottom: 5,
    paddingLeft: 50,
    color: 'white',
  },
  numberList: {
    marginBottom: 10,
    marginTop: 10,
    paddingLeft: 10,
    color: 'white',
  },
  background: {
    position: 'absolute',
    top: 0,
    left: 0,
    width: '137%',
    height: '125%',
    zIndex: -1,
  },
});

const PDFDocument = ({ content }) => {
  const tokens = md.parse(content, {});
  let listCounter = 1;
  let prevContent = '';

  return (
    <Document>
      <Page style={styles.page}>
        <Image fixed style={styles.background} src='/images/pdf_background.png' />
        <View>
          {tokens.map((token, index) => {
            if (token.type === 'heading_open') {
              if (token.tag === 'h1') {
                return <Text key={index} style={styles.header1}>{tokens[index + 1].content}</Text>;
              }
              if (token.tag === 'h3') {
                return <Text key={index} style={styles.header2}>{tokens[index + 1].content}</Text>;
              }
            }
            if (token.type === 'paragraph_open') {
              if (tokens[index + 1].content === prevContent) {
                return;
              } else {
                return <Text key={index} style={styles.text}>{tokens[index + 1].content}</Text>;
              }
            }
            if (token.type === 'ordered_list_open') {
              listCounter = 1;
            }
            if (token.type === 'list_item_open') {
              let listItemContent;
              if (token.markup === '-') {
                listItemContent = `• ${tokens[index + 2].content}`;
                prevContent = tokens[index + 2].content;
              } else if (token.markup === '.') {
                listItemContent = `${listCounter}. ${tokens[index + 2].content}`;
                listCounter += 1;
                prevContent = tokens[index + 2].content;
              }
              return <View key={index}><Text style={token.markup === '-' ? styles.bulletList : styles.numberList}>{listItemContent}</Text></View>;
            }
            return null;
          })}
        </View>
      </Page>
    </Document>
  );
};


export default PDFDocument;
