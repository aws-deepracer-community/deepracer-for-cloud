#include "mainwindow.h"
#include <QApplication>

int main(int argc, char *argv[])
{
    QApplication a(argc, argv);
    MainWindow w;
//    QTextEdit *reward_function = new QTextEdit();
//    reward_function->setText("Hello, world!");
//    reward_function->append("Appending some text…");
    w.showMaximized();

    return a.exec();
}
